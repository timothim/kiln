import SwiftUI

/// Right pane during `.preparing`. Shows what Kiln looks for, with counts
/// pending (—). Real counts will land in M2/M3 when the ingest pipeline wires
/// through.
struct PrepareDetailView: View {
    struct ScanCategory: Identifiable {
        let id: String
        let symbol: String
        let label: String
    }

    private let categories: [ScanCategory] = [
        ScanCategory(id: "text",    symbol: "doc.text",     label: "Text"),
        ScanCategory(id: "msg",     symbol: "bubble.left",  label: "Messages"),
        ScanCategory(id: "code",    symbol: "curlybraces",  label: "Code"),
        ScanCategory(id: "email",   symbol: "envelope",     label: "Email"),
        ScanCategory(id: "notes",   symbol: "book.closed",  label: "Notes"),
    ]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: Kiln.Space.m) {
                Text("Scanning")
                    .font(Kiln.Font.title)
                    .foregroundStyle(.primary)

                Text("Kiln reads these formats.")
                    .font(Kiln.Font.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, Kiln.Space.xs)

                VStack(spacing: 2) {
                    ForEach(categories) { category in
                        ScanRow(category: category)
                    }
                }

                Spacer()
            }
            .padding(Kiln.Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct ScanRow: View {
    let category: PrepareDetailView.ScanCategory

    var body: some View {
        HStack(spacing: Kiln.Space.xs) {
            Image(systemName: category.symbol)
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(category.label)
                .font(Kiln.Font.body)
                .foregroundStyle(.primary)

            Spacer(minLength: Kiln.Space.xs)

            Text("—")
                .font(Kiln.Font.mono)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Kiln.Space.xs)
        .padding(.horizontal, Kiln.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.label) count pending")
    }
}
