import Foundation

public struct DiscoveredFile: Hashable, Sendable {
    public let url: URL
    public let sizeBytes: Int

    public init(url: URL, sizeBytes: Int) {
        self.url = url
        self.sizeBytes = sizeBytes
    }
}

public enum FileDiscovery {
    /// Recursively walk `root`, returning regular-file URLs sorted by path.
    /// Skips hidden entries (names starting with "."), names in `excludedDirNames`,
    /// symlinks, and files larger than `maxFileBytes`.
    public static func walk(
        _ root: URL,
        excludedDirNames: Set<String>,
        maxFileBytes: Int
    ) throws -> [DiscoveredFile] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw IngestError.directoryNotFound(root)
        }

        var out: [DiscoveredFile] = []
        try walk(
            directory: root,
            fm: fm,
            excludedDirNames: excludedDirNames,
            maxFileBytes: maxFileBytes,
            into: &out
        )
        out.sort { $0.url.path < $1.url.path }
        return out
    }

    private static func walk(
        directory: URL,
        fm: FileManager,
        excludedDirNames: Set<String>,
        maxFileBytes: Int,
        into out: inout [DiscoveredFile]
    ) throws {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .nameKey
        ]
        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsSubdirectoryDescendants]
        )
        for url in contents {
            let values = try url.resourceValues(forKeys: keys)
            let name = values.name ?? url.lastPathComponent
            if name.hasPrefix(".") { continue }
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                if excludedDirNames.contains(name) { continue }
                try walk(
                    directory: url,
                    fm: fm,
                    excludedDirNames: excludedDirNames,
                    maxFileBytes: maxFileBytes,
                    into: &out
                )
            } else if values.isRegularFile == true {
                let size = values.fileSize ?? 0
                if size > maxFileBytes { continue }
                out.append(DiscoveredFile(url: url, sizeBytes: size))
            }
        }
    }
}
