import SwiftUI

/// Right pane during `.training`. Streaming log entries in monospace. M3 uses
/// a typed placeholder list shaped like the IPC progress events defined in
/// SPEC §11; M5 will replace the source without touching the view.
struct LogsPanel: View {
    let project: Project

    struct Entry: Identifiable, Hashable {
        let id: Int
        let time: String
        let text: String
    }

    private var entries: [Entry] {
        [
            Entry(id: 0, time: "00:00:02", text: "sidecar ready · mlx 0.16.0"),
            Entry(id: 1, time: "00:00:03", text: "sft start · qwen2.5-\(project.modelSize.displayName.lowercased())"),
            Entry(id: 2, time: "00:00:42", text: "iter 50    loss 1.84   tokens/s 3,200"),
            Entry(id: 3, time: "00:01:18", text: "iter 100   loss 1.52   tokens/s 3,180"),
            Entry(id: 4, time: "00:01:54", text: "checkpoint saved · iter 100"),
            Entry(id: 5, time: "00:02:31", text: "iter 150   loss 1.34   tokens/s 3,210"),
        ]
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                logList
            }
        }
    }

    private var header: some View {
        HStack(spacing: Kiln.Space.xs) {
            Text("Log")
                .font(Kiln.Font.title)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Text("live")
                .font(Kiln.Font.caption)
                .foregroundStyle(Kiln.Palette.accent)
        }
        .padding(.horizontal, Kiln.Space.s)
        .padding(.vertical, Kiln.Space.s)
    }

    private var logList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kiln.Space.xs - 2) {
                ForEach(entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.xs) {
                        Text(entry.time)
                            .font(Kiln.Font.mono)
                            .foregroundStyle(.tertiary)
                        Text(entry.text)
                            .font(Kiln.Font.mono)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Kiln.Space.s)
            .padding(.vertical, Kiln.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
