import XCTest
import CryptoKit
@testable import KilnCore

final class ShareExporterTests: XCTestCase {

    // MARK: - Fixtures

    private func makeTempDir(_ label: String = "kiln-export-test") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct Fixture {
        let workDir: URL
        let adapter: URL
        let adapterBytes: Data
        let modelfile: URL
        let modelfileText: String
        let destination: URL
    }

    private func makeFixture() throws -> Fixture {
        let work = try makeTempDir()
        let adapter = work.appendingPathComponent("adapter.safetensors")
        let adapterBytes = Data((0..<1024).map { UInt8($0 % 256) })
        try adapterBytes.write(to: adapter)

        let modelfile = work.appendingPathComponent("Modelfile")
        let modelfileText = """
        FROM kiln/tim-drafts:latest
        PARAMETER temperature 0.8
        """
        try modelfileText.write(to: modelfile, atomically: true, encoding: .utf8)

        let dest = work.appendingPathComponent("out.kiln")
        return Fixture(
            workDir: work,
            adapter: adapter,
            adapterBytes: adapterBytes,
            modelfile: modelfile,
            modelfileText: modelfileText,
            destination: dest
        )
    }

    /// Unzip helper — asserts that entries exist with the expected bytes.
    /// Uses `/usr/bin/unzip` for round-trip symmetry with the exporter.
    private func unzip(_ archive: URL, to dest: URL) throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", archive.path, "-d", dest.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "unzip returned \(process.terminationStatus)")
    }

    // MARK: - Export happy-path

    func testExportProducesZipWithAdapterAndModelfile() async throws {
        let f = try makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: f.workDir) }

        let exporter = ShareExporter()
        let bundle = try await exporter.export(
            ShareManifest(
                voiceName: "tim-drafts",
                adapterURL: f.adapter,
                modelfileURL: f.modelfile
            ),
            to: f.destination
        )

        XCTAssertEqual(bundle.bundleURL, f.destination)
        XCTAssertGreaterThan(bundle.sizeBytes, 0)
        XCTAssertEqual(bundle.sha256.count, 64, "SHA-256 should be a 64-char hex string")
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.destination.path))

        // Unzip and verify entries.
        let unzipped = try makeTempDir("unzipped")
        addTeardownBlock { try? FileManager.default.removeItem(at: unzipped) }
        try unzip(f.destination, to: unzipped)

        let adapterOut = unzipped.appendingPathComponent("adapter.safetensors")
        let modelfileOut = unzipped.appendingPathComponent("Modelfile")
        let manifestOut = unzipped.appendingPathComponent("manifest.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: adapterOut.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelfileOut.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestOut.path))

        // Bytes round-trip intact.
        let adapterRoundTrip = try Data(contentsOf: adapterOut)
        XCTAssertEqual(adapterRoundTrip, f.adapterBytes)
        let modelfileRoundTrip = try String(contentsOf: modelfileOut, encoding: .utf8)
        XCTAssertEqual(modelfileRoundTrip, f.modelfileText)
    }

    func testExportIncludesOptionalReadmeAndSignature() async throws {
        let f = try makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: f.workDir) }

        let readme = "# Tim — drafts\n\nImport with `ollama create`.\n"
        let png = Data(repeating: 0xAB, count: 128)

        let exporter = ShareExporter()
        _ = try await exporter.export(
            ShareManifest(
                voiceName: "tim-drafts",
                adapterURL: f.adapter,
                modelfileURL: f.modelfile,
                readmeText: readme,
                signatureCardPNG: png
            ),
            to: f.destination
        )

        let unzipped = try makeTempDir("unzipped-optional")
        addTeardownBlock { try? FileManager.default.removeItem(at: unzipped) }
        try unzip(f.destination, to: unzipped)

        let readmeOut = unzipped.appendingPathComponent("README.md")
        let signatureOut = unzipped.appendingPathComponent("signature.png")

        XCTAssertTrue(FileManager.default.fileExists(atPath: readmeOut.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: signatureOut.path))

        XCTAssertEqual(try String(contentsOf: readmeOut, encoding: .utf8), readme)
        XCTAssertEqual(try Data(contentsOf: signatureOut), png)
    }

    func testExportOmitsUntickedOptionalFiles() async throws {
        let f = try makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: f.workDir) }

        let exporter = ShareExporter()
        _ = try await exporter.export(
            ShareManifest(
                voiceName: "tim-drafts",
                adapterURL: f.adapter,
                modelfileURL: f.modelfile
                // readmeText + signatureCardPNG + sourceManifestText all nil
            ),
            to: f.destination
        )

        let unzipped = try makeTempDir("unzipped-minimal")
        addTeardownBlock { try? FileManager.default.removeItem(at: unzipped) }
        try unzip(f.destination, to: unzipped)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath:
                unzipped.appendingPathComponent("README.md").path),
            "README was not requested — it must not ship"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath:
                unzipped.appendingPathComponent("signature.png").path),
            "Signature card was not requested — it must not ship"
        )
    }

    func testManifestJSONCarriesShaOfEveryFile() async throws {
        let f = try makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: f.workDir) }

        let exporter = ShareExporter()
        _ = try await exporter.export(
            ShareManifest(
                voiceName: "tim-drafts",
                adapterURL: f.adapter,
                modelfileURL: f.modelfile,
                readmeText: "# readme"
            ),
            to: f.destination
        )

        let unzipped = try makeTempDir("unzipped-manifest")
        addTeardownBlock { try? FileManager.default.removeItem(at: unzipped) }
        try unzip(f.destination, to: unzipped)

        let manifestURL = unzipped.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        struct Payload: Decodable {
            let voice: String
            let format: String
            let files: [String: String]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: manifestData)

        XCTAssertEqual(payload.voice, "tim-drafts")
        XCTAssertEqual(payload.format, "kiln/v1")
        XCTAssertNotNil(payload.files["adapter.safetensors"])
        XCTAssertNotNil(payload.files["Modelfile"])
        XCTAssertNotNil(payload.files["README.md"])

        // Verify each listed SHA matches the file's actual bytes — catches
        // any manifest/content drift at export time.
        for (name, expectedSha) in payload.files {
            let url = unzipped.appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            let actualSha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(expectedSha, actualSha, "sha mismatch for \(name)")
        }
    }

    // MARK: - Error paths

    func testExportFailsWhenAdapterMissing() async throws {
        let f = try makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: f.workDir) }

        let missingAdapter = f.workDir.appendingPathComponent("nope.safetensors")
        let manifest = ShareManifest(
            voiceName: "tim-drafts",
            adapterURL: missingAdapter,
            modelfileURL: f.modelfile
        )

        let exporter = ShareExporter()
        do {
            _ = try await exporter.export(manifest, to: f.destination)
            XCTFail("Expected missingAdapter")
        } catch let ShareExporterError.missingAdapter(url) {
            XCTAssertEqual(url, missingAdapter)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExportFailsWhenModelfileMissing() async throws {
        let f = try makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: f.workDir) }

        let missingModelfile = f.workDir.appendingPathComponent("no-modelfile")
        let manifest = ShareManifest(
            voiceName: "tim-drafts",
            adapterURL: f.adapter,
            modelfileURL: missingModelfile
        )

        let exporter = ShareExporter()
        do {
            _ = try await exporter.export(manifest, to: f.destination)
            XCTFail("Expected missingModelfile")
        } catch let ShareExporterError.missingModelfile(url) {
            XCTAssertEqual(url, missingModelfile)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExportFailsWhenZipBinaryMissing() async throws {
        let f = try makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: f.workDir) }

        let bogusZip = URL(fileURLWithPath: "/path/does/not/exist/zip")
        let exporter = ShareExporter(zipURL: bogusZip)
        do {
            _ = try await exporter.export(
                ShareManifest(
                    voiceName: "tim-drafts",
                    adapterURL: f.adapter,
                    modelfileURL: f.modelfile
                ),
                to: f.destination
            )
            XCTFail("Expected zipUnavailable")
        } catch ShareExporterError.zipUnavailable {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - KilnShare.export wrapper

    func testKilnShareExportManifestDelegatesToExporter() async throws {
        let f = try makeFixture()
        addTeardownBlock { try? FileManager.default.removeItem(at: f.workDir) }

        let manifest = ShareManifest(
            voiceName: "tim-drafts",
            adapterURL: f.adapter,
            modelfileURL: f.modelfile
        )
        let bundle = try await KilnShare.export(
            manifest: manifest,
            to: f.destination
        )

        XCTAssertEqual(bundle.bundleURL, f.destination)
        XCTAssertGreaterThan(bundle.sizeBytes, 0)
    }
}
