import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Export result

/// Status message shown next to the Export button after a tap. `nil` message
/// means the user cancelled the save panel — we render nothing rather than a
/// "cancelled" line, which reads as scolding for an intentional action.
struct ExportResult: Equatable {
    let message: String?
}

// MARK: - Exporter

/// Renders `StyleSignatureCardArt` at 3× scale and writes a PNG via
/// `CGImageDestination`. Writes the card summary + attribution into PNG tEXt
/// chunks so a re-import path can recover provenance.
///
/// Called from `StyleSignatureCardView`'s Export button. M7 (DATA) may add a
/// second entry point that exports without user confirmation (for Kiln Share
/// bundle packaging) — keep `exportPNG` user-facing; factor a private writer
/// if that second caller arrives.
enum StyleSignatureExporter {
    @MainActor
    static func exportPNG(signature: StyleSignature) -> ExportResult {
        let renderer = ImageRenderer(content: StyleSignatureCardArt(signature: signature))
        renderer.scale = 3.0

        guard let cgImage = renderer.cgImage else {
            return ExportResult(message: "Export failed — could not render.")
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(signature.userLabel)-kiln-voice.png"
        panel.title = "Export Style Signature"
        panel.prompt = "Export"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            return ExportResult(message: nil)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            return ExportResult(message: "Export failed — could not open destination.")
        }

        let pngMetadata: [CFString: Any] = [
            kCGImagePropertyPNGTitle:       "\(signature.userLabel) — Kiln voice signature",
            kCGImagePropertyPNGSoftware:    "Kiln",
            kCGImagePropertyPNGSource:      "https://github.com/timothim/kiln",
            kCGImagePropertyPNGDescription: signature.summary
        ]
        let properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: pngMetadata
        ]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return ExportResult(message: "Export failed — could not write file.")
        }

        return ExportResult(message: "Saved to \(url.lastPathComponent).")
    }
}
