import Foundation
import CryptoKit
import OSLog

/// Describes the inputs to a single `.kiln` export. Built by the UI layer
/// from the user's include-options and the current voice's on-disk artifacts.
///
/// `adapterURL` and `modelfileURL` are required — everything else is optional
/// so the caller can omit sections the user unticked on the sheet.
public struct ShareManifest: Sendable, Equatable {
    public let voiceName: String
    public let adapterURL: URL
    public let modelfileURL: URL
    public let readmeText: String?
    public let signatureCardPNG: Data?
    public let sourceManifestText: String?

    public init(
        voiceName: String,
        adapterURL: URL,
        modelfileURL: URL,
        readmeText: String? = nil,
        signatureCardPNG: Data? = nil,
        sourceManifestText: String? = nil
    ) {
        self.voiceName = voiceName
        self.adapterURL = adapterURL
        self.modelfileURL = modelfileURL
        self.readmeText = readmeText
        self.signatureCardPNG = signatureCardPNG
        self.sourceManifestText = sourceManifestText
    }
}

public enum ShareExporterError: Error, Equatable {
    case missingAdapter(URL)
    case missingModelfile(URL)
    case copyFailed(URL, String)
    case zipUnavailable
    case zipFailed(exitCode: Int32, stderr: String)
    case outputNotProduced(URL)
}

/// Packages a trained voice as a single `.kiln` file — a zip containing the
/// fused adapter, the Ollama Modelfile, and optional README / signature card
/// / source manifest. Structured as an actor because the staging directory
/// handling is mutable-state-per-export and we never want two concurrent
/// exports stepping on the same temp dir.
///
/// Why shell out to `/usr/bin/zip` rather than use `AppleArchive` or a Swift
/// zip library: `zip` is guaranteed present on every macOS install, produces
/// a standard deflate archive any Ollama user can extract, and avoids adding
/// a KilnCore dependency (package-rule: Foundation / OSLog / CryptoKit /
/// CoreML only). The subprocess call stays inside this actor so the
/// sandboxing surface is small.
public actor ShareExporter {
    private let log = Logger(subsystem: "app.kiln.core", category: "ShareExporter")
    private let zipURL: URL
    private let fm: FileManager

    public init(zipURL: URL = URL(fileURLWithPath: "/usr/bin/zip"),
                fileManager: FileManager = .default) {
        self.zipURL = zipURL
        self.fm = fileManager
    }

    /// Produce a `.kiln` bundle at `destinationURL`. Returns a `KilnShare.Bundle`
    /// with the final size and SHA-256 so the UI's success block can show
    /// both. Throws a typed `ShareExporterError` — no `fatalError` / no
    /// force-unwrap (per `packages/KilnCore/CLAUDE.md`).
    public func export(_ manifest: ShareManifest,
                       to destinationURL: URL) async throws -> KilnShare.Bundle {
        guard fm.fileExists(atPath: manifest.adapterURL.path) else {
            throw ShareExporterError.missingAdapter(manifest.adapterURL)
        }
        guard fm.fileExists(atPath: manifest.modelfileURL.path) else {
            throw ShareExporterError.missingModelfile(manifest.modelfileURL)
        }
        guard fm.fileExists(atPath: zipURL.path) else {
            throw ShareExporterError.zipUnavailable
        }

        let staging = try makeStagingDir()
        defer { try? fm.removeItem(at: staging) }

        try stageFile(from: manifest.adapterURL,
                      to: staging.appendingPathComponent("adapter.safetensors"))
        try stageFile(from: manifest.modelfileURL,
                      to: staging.appendingPathComponent("Modelfile"))

        if let readme = manifest.readmeText {
            let url = staging.appendingPathComponent("README.md")
            try writeText(readme, to: url)
        }
        if let png = manifest.signatureCardPNG {
            let url = staging.appendingPathComponent("signature.png")
            try writeData(png, to: url)
        }
        if let sources = manifest.sourceManifestText {
            let url = staging.appendingPathComponent("sources.txt")
            try writeText(sources, to: url)
        }

        // Generate our own manifest.json with the SHA-256 of each file so
        // recipients can detect tampering. Written last so it includes every
        // other file but not itself.
        let shaMap = try shaMap(for: staging)
        let manifestJSON = try makeManifestJSON(voiceName: manifest.voiceName,
                                                shas: shaMap)
        let manifestURL = staging.appendingPathComponent("manifest.json")
        try writeData(manifestJSON, to: manifestURL)

        // Remove an existing destination file so zip -j doesn't append.
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        try runZip(stagingDir: staging, destination: destinationURL)

        guard fm.fileExists(atPath: destinationURL.path) else {
            throw ShareExporterError.outputNotProduced(destinationURL)
        }

        let finalData = try Data(contentsOf: destinationURL)
        let hash = SHA256.hash(data: finalData)
        let hex = hash.map { String(format: "%02x", $0) }.joined()

        return KilnShare.Bundle(
            bundleURL: destinationURL,
            sizeBytes: finalData.count,
            sha256: hex
        )
    }

    // MARK: - Staging helpers

    private func makeStagingDir() throws -> URL {
        let url = fm.temporaryDirectory
            .appendingPathComponent("kiln-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func stageFile(from src: URL, to dst: URL) throws {
        do {
            try fm.copyItem(at: src, to: dst)
        } catch {
            throw ShareExporterError.copyFailed(src, error.localizedDescription)
        }
    }

    private func writeText(_ string: String, to url: URL) throws {
        guard let data = string.data(using: .utf8) else {
            throw ShareExporterError.copyFailed(url, "utf-8 encoding failed")
        }
        try writeData(data, to: url)
    }

    private func writeData(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ShareExporterError.copyFailed(url, error.localizedDescription)
        }
    }

    private func shaMap(for dir: URL) throws -> [String: String] {
        let contents = try fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var result: [String: String] = [:]
        for url in contents {
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data)
            result[url.lastPathComponent] = digest.map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    private func makeManifestJSON(voiceName: String,
                                  shas: [String: String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = ManifestPayload(
            voice: voiceName,
            format: "kiln/v1",
            files: shas
        )
        return try encoder.encode(payload)
    }

    // MARK: - zip subprocess

    /// Runs `/usr/bin/zip -r -j -X -q <destination> <staging>/`. Flags:
    ///   -r  recurse into the staging dir
    ///   -j  junk paths (so entries are `Modelfile` not `staging/Modelfile`)
    ///   -X  strip extra file attributes (reduces reproducibility drift)
    ///   -q  quiet
    private func runZip(stagingDir: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = zipURL
        process.arguments = [
            "-r", "-j", "-X", "-q",
            destination.path,
            stagingDir.path
        ]

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw ShareExporterError.zipFailed(
                exitCode: -1,
                stderr: "failed to spawn zip: \(error.localizedDescription)"
            )
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            log.error("zip exit \(process.terminationStatus): \(text, privacy: .public)")
            throw ShareExporterError.zipFailed(
                exitCode: process.terminationStatus,
                stderr: text
            )
        }
    }

    private struct ManifestPayload: Encodable {
        let voice: String
        let format: String
        let files: [String: String]
    }
}
