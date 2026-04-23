import SwiftUI

/// Stage 3 — training complete. Confident header, stat grid, and the Terminal
/// hand-off line in monospace. No exclamation marks (one is reserved for the
/// final export-success moment when Ollama confirms).
struct CompleteStageView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            VStack(alignment: .leading, spacing: Kiln.Space.xs) {
                HStack(spacing: Kiln.Space.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: Kiln.Icon.heading))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("\(project.name) is ready")
                        .font(Kiln.Font.display)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    StageBadge(stage: project.stage)
                }

                Text("Your model is trained. Open Terminal to chat.")
                    .font(Kiln.Font.body)
                    .foregroundStyle(.secondary)
            }

            statsRow
                .frame(maxWidth: 640)
                .padding(.top, Kiln.Space.xs)

            terminalLine
                .padding(.top, Kiln.Space.xs)

            Spacer(minLength: 0)
        }
        .padding(Kiln.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statsRow: some View {
        HStack(spacing: Kiln.Space.s) {
            Stat(label: "Model", value: "Qwen2.5-\(project.modelSize.displayName)")
            Stat(
                label: "Chunks",
                value: chunksValue
            )
            Stat(
                label: "Trained",
                value: project.lastTrained
                    .map { $0.formatted(.relative(presentation: .named)) }
                    ?? "just now"
            )
        }
    }

    private var chunksValue: String {
        if let kept = project.keptChunks, let total = project.totalChunks {
            return "\(kept.formatted()) of \(total.formatted())"
        }
        return "—"
    }

    private var terminalLine: some View {
        HStack(spacing: Kiln.Space.xs) {
            Image(systemName: "terminal")
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("ollama run kiln-\(project.slug)")
                .font(Kiln.Font.mono)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Kiln.Space.s)
        .padding(.vertical, Kiln.Space.xs)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Terminal command: ollama run kiln dash \(project.slug)")
    }
}
