import SwiftUI
import KilnCore

/// Completion summary — what the pipeline kept, what it rejected, and the
/// amber CTA to move on to training.
struct DatasetDoctorView: View {
    let project: Project
    let report: IngestReport
    let onContinue: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.m) {
            StageHeader(
                title: project.name,
                subtitle: subtitle,
                stage: project.stage
            )
            funnelRow
            qualitySection
            if report.filesSkipped.count > 0 {
                skippedFooter
            }
            Spacer(minLength: 0)
            ctaRow
        }
        .padding(Kiln.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var subtitle: String {
        "Kept \(report.chunksAfterQuality) samples from \(report.filesParsed) files."
    }

    private var funnelRow: some View {
        HStack(alignment: .top, spacing: Kiln.Space.m) {
            LiveCountTicker(label: "Files read", value: report.filesParsed)
            LiveCountTicker(label: "Chunks", value: report.chunksBeforeDedup)
            LiveCountTicker(label: "Exact unique", value: report.chunksAfterExactDedup)
            LiveCountTicker(label: "Near unique", value: report.chunksAfterMinHashDedup)
            LiveCountTicker(label: "Kept", value: report.chunksAfterQuality)
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.xs) {
            Text("Why samples were dropped")
                .font(Kiln.Font.caption)
                .foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: Kiln.Space.xxs) {
                breakdownRow("Too short", report.qualityBreakdown.hardRejected.tooShort + report.qualityBreakdown.softRejected.tooShort)
                breakdownRow("Wrong language", report.qualityBreakdown.hardRejected.wrongLanguage + report.qualityBreakdown.softRejected.wrongLanguage)
                breakdownRow("Too repetitive", report.qualityBreakdown.hardRejected.tooRepetitive + report.qualityBreakdown.softRejected.tooRepetitive)
                breakdownRow("Too much non-ASCII", report.qualityBreakdown.hardRejected.tooMuchNonASCII + report.qualityBreakdown.softRejected.tooMuchNonASCII)
            }
        }
    }

    private func breakdownRow(_ label: String, _ count: Int) -> some View {
        HStack {
            Text(label)
                .font(Kiln.Font.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count)")
                .font(Kiln.Font.body)
                .monospacedDigit()
                .foregroundStyle(count > 0 ? .primary : .tertiary)
        }
    }

    private var skippedFooter: some View {
        Text("\(report.filesSkipped.count) files skipped.")
            .font(Kiln.Font.caption)
            .foregroundStyle(.tertiary)
    }

    private var ctaRow: some View {
        HStack {
            Button("Drop another folder", action: onReset)
            Spacer()
            Button(action: onContinue) {
                Label("Continue to training", systemImage: "arrow.right")
                    .font(Kiln.Font.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Kiln.Space.s)
                    .padding(.vertical, Kiln.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                            .fill(Kiln.Palette.accent)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Continue to training")
        }
    }
}
