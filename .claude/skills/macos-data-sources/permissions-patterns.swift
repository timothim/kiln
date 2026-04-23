// permissions-patterns.swift
// Kiln — macOS permission and file-access patterns for data ingest.
// See macos-data-sources/SKILL.md for the full catalog.
//
// These snippets are canonical copies. When behavior changes, update both
// this file and the SKILL. The Kiln ingest layer at
// packages/KilnCore/Sources/KilnCore/Ingest/ calls these verbatim.

import AppKit
import Foundation
import SQLite3

// SQLITE_TRANSIENT isn't bridged by the stdlib overlay; define locally.
// Must be a sqlite3_destructor_type whose bit-pattern is -1.
let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)

// MARK: - §1. NSOpenPanel for folder drop / vault pick / sandbox container

enum FolderPick {
    /// Present a modal NSOpenPanel and return the chosen folder URL.
    /// Call on the main actor.
    @MainActor
    static func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - §2. Security-scoped bookmarks

enum BookmarkStore {
    /// Persist a bookmark under ~/.kiln/bookmarks/<key>.bookmark.
    static func save(_ url: URL, key: String) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let dir = URL.homeDirectory.appending(path: ".kiln/bookmarks")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appending(path: "\(key).bookmark"), options: .atomic)
    }

    /// Resolve a previously-saved bookmark.
    /// Returns nil if the bookmark doesn't exist OR is stale; caller should re-prompt.
    static func resolve(key: String) throws -> URL? {
        let path = URL.homeDirectory
            .appending(path: ".kiln/bookmarks/\(key).bookmark")
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return isStale ? nil : url
    }

    /// Standard access pattern: start/stop around the read.
    static func withAccess<T>(to url: URL, _ body: (URL) throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}

// MARK: - §3. Full Disk Access probe + chat.db copy

enum TCCProbe {
    /// Returns true if Full Disk Access is granted for this process.
    /// No public API exists for TCC status; the canonical probe is to try
    /// to open TCC.db read-only.
    static func hasFullDiskAccess() -> Bool {
        let tccPath = "/Library/Application Support/com.apple.TCC/TCC.db"
        let fd = open(tccPath, O_RDONLY)
        if fd >= 0 { close(fd); return true }
        return false
    }

    /// Open System Settings at the Full Disk Access pane.
    @MainActor
    static func openSettingsToFullDiskAccess() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )!
        NSWorkspace.shared.open(url)
    }
}

enum ChatDBCopy {
    /// Copy chat.db + WAL/SHM sidecars to a unique temp dir and return the copy URL.
    /// Must be called AFTER `TCCProbe.hasFullDiskAccess()` returns true.
    /// Returns nil on failure (permission denied, disk full, etc.).
    static func copyForRead() -> URL? {
        let srcDir = URL.homeDirectory.appending(path: "Library/Messages")
        let src = srcDir.appending(path: "chat.db")
        let dstDir = FileManager.default.temporaryDirectory
            .appending(path: "kiln-chatdb-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(
                at: dstDir, withIntermediateDirectories: true)
            let dst = dstDir.appending(path: "chat.db")
            try FileManager.default.copyItem(at: src, to: dst)
            // Sidecars — missing is OK (database in checkpoint state).
            for sidecar in ["chat.db-shm", "chat.db-wal"] {
                let s = srcDir.appending(path: sidecar)
                if FileManager.default.fileExists(atPath: s.path) {
                    try? FileManager.default.copyItem(
                        at: s,
                        to: dstDir.appending(path: sidecar)
                    )
                }
            }
            return dst
        } catch {
            return nil
        }
    }
}

// MARK: - §4. SQLite UDF for attributedBody decoding

/// Register `kiln_extract_attributedbody(BLOB) -> TEXT` on a SQLite connection.
/// Decodes NSKeyedArchiver blobs from `message.attributedBody` and returns the
/// embedded plain text. Returns NULL on decode failure.
///
/// Without this UDF, Q1 in chat-db-schema.sql returns empty body strings for
/// roughly 30% of recent messages (iOS 16+ writes attributedBody instead of text).
func registerAttributedBodyExtractor(_ db: OpaquePointer) {
    _ = sqlite3_create_function_v2(
        db,
        "kiln_extract_attributedbody",
        1, // argc
        SQLITE_UTF8,
        nil, // user data
        { ctx, _, argv in
            guard
                let argv,
                let raw = argv[0],
                sqlite3_value_type(raw) == SQLITE_BLOB,
                let ptr = sqlite3_value_blob(raw)
            else {
                sqlite3_result_null(ctx)
                return
            }
            let n = Int(sqlite3_value_bytes(raw))
            let data = Data(bytes: ptr, count: n)
            guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else {
                sqlite3_result_null(ctx)
                return
            }
            unarchiver.requiresSecureCoding = false
            let classes: [AnyClass] = [
                NSAttributedString.self,
                NSMutableAttributedString.self,
                NSString.self,
                NSMutableString.self,
            ]
            let obj = unarchiver.decodeObject(
                of: classes, forKey: NSKeyedArchiveRootObjectKey)
            let text: String? = {
                if let s = obj as? NSAttributedString { return s.string }
                if let s = obj as? String { return s }
                return nil
            }()
            if let t = text, !t.isEmpty {
                t.withCString { cstr in
                    sqlite3_result_text(ctx, cstr, -1, SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_result_null(ctx)
            }
        },
        nil, nil, nil
    )
}

// MARK: - §5. Obsidian vault detection + frontmatter strip

enum ObsidianVault {
    /// True if `url` is an Obsidian vault (contains a `.obsidian/` subfolder).
    static func isVault(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let marker = url.appending(path: ".obsidian")
        return FileManager.default.fileExists(
            atPath: marker.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Strip YAML frontmatter if present. Returns (frontmatter, body).
    /// Handles `---\n` and `---\r\n` leading delimiters.
    static func splitFrontmatter(_ text: String) -> (fm: String?, body: String) {
        let leadLF = "---\n"
        let leadCRLF = "---\r\n"
        let leadLen: Int
        if text.hasPrefix(leadCRLF) {
            leadLen = leadCRLF.count
        } else if text.hasPrefix(leadLF) {
            leadLen = leadLF.count
        } else {
            return (nil, text)
        }
        let rest = text.dropFirst(leadLen)
        guard
            let endRange = rest.range(of: "\n---\n")
                ?? rest.range(of: "\n---\r\n")
                ?? rest.range(of: "\n---")
        else { return (nil, text) }
        let fm = String(rest[..<endRange.lowerBound])
        let body = String(rest[endRange.upperBound...])
        return (fm, body)
    }

    /// Strip Obsidian-specific link syntax.
    /// Embed links (`![[x]]`) are removed entirely; wikilinks
    /// (`[[target]]` or `[[target|display]]`) become `target` or `display`.
    static func stripWikilinks(_ text: String) -> String {
        var out = text
        let embedPat = #"!\[\[[^\]]*\]\]"#
        out = out.replacingOccurrences(
            of: embedPat, with: "", options: .regularExpression)
        // [[target]]
        let simplePat = #"\[\[([^\]|]+)\]\]"#
        out = out.replacingOccurrences(
            of: simplePat, with: "$1", options: .regularExpression)
        // [[target|display]]
        let aliasPat = #"\[\[[^\]|]+\|([^\]]+)\]\]"#
        out = out.replacingOccurrences(
            of: aliasPat, with: "$1", options: .regularExpression)
        // ^blockid on its own line
        let blockPat = #"(?m)^\s*\^[a-zA-Z0-9-]+\s*$"#
        out = out.replacingOccurrences(
            of: blockPat, with: "", options: .regularExpression)
        // %%comment%%
        let commentPat = #"%%[\s\S]*?%%"#
        out = out.replacingOccurrences(
            of: commentPat, with: "", options: .regularExpression)
        return out
    }
}

// MARK: - §6. Usage sketch (not compiled; read as the canonical flow)
//
// @MainActor
// func ingestMessages(model: AppModel) async throws {
//     guard TCCProbe.hasFullDiskAccess() else {
//         TCCProbe.openSettingsToFullDiskAccess()
//         throw KilnIngestError.missingFullDiskAccess
//     }
//     guard let copy = ChatDBCopy.copyForRead() else {
//         throw KilnIngestError.chatDBCopyFailed
//     }
//     var db: OpaquePointer?
//     defer { if let db { sqlite3_close(db) } }
//     let rc = sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil)
//     precondition(rc == SQLITE_OK)
//     registerAttributedBodyExtractor(db!)
//     // …run Q1 from chat-db-schema.sql, stream rows into the training corpus…
// }
