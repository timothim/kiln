import SwiftUI
import KilnCore

/// Completion summary — what the pipeline kept, what it rejected, and the
/// amber CTA to move on to training.
struct DatasetDoctorView: View {
    let project: Project
    let report: IngestReport
    let onContinue: () -> Void
    let onReset: () -> Void
    /// Audit C3: when non-nil, a "Run Deep Curation" CTA appears in
    /// the action row. Closure opens the Managed-Agent sheet via
    /// ``AppModel.openDeepCuration(for:)``.
    var onOpenDeepCuration: (() -> Void)? = nil
    var deepCurationModel: DeepCurationModel? = nil
    var onCloseDeepCuration: (() -> Void)? = nil

    private var deepCurationIsPresented: Binding<Bool> {
        Binding(
            get: { deepCurationModel != nil },
            set: { newValue in
                if !newValue { onCloseDeepCuration?() }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Kiln.Space.l) {
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
        .padding(Kiln.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: deepCurationIsPresented) {
            if let model = deepCurationModel {
                DeepCurationSheet(
                    model: model,
                    onClose: { onCloseDeepCuration?() }
                )
            }
        }
    }

    private var subtitle: String {
        let kept = classifierGateActive ? report.chunksAfterClassifierQuality : report.chunksAfterQuality
        return "Kept \(kept) samples from \(report.filesParsed) files."
    }

    /// True when the M9.C classifier gate ran on this corpus (any
    /// chunk landed in any bucket). When false the gate degraded to
    /// a no-op and the funnel row hides the extra ticker so the user
    /// doesn't see a meaningless duplicate of "Kept".
    private var classifierGateActive: Bool {
        report.classifierBuckets.total > 0
    }

    private var funnelRow: some View {
        HStack(alignment: .top, spacing: Kiln.Space.l) {
            LiveCountTicker(label: "Files read", value: report.filesParsed)
            LiveCountTicker(label: "Chunks", value: report.chunksBeforeDedup)
            LiveCountTicker(label: "Exact unique", value: report.chunksAfterExactDedup)
            LiveCountTicker(label: "Near unique", value: report.chunksAfterMinHashDedup)
            LiveCountTicker(label: "Length-passed", value: report.chunksAfterQuality)
            if classifierGateActive {
                // Fourth (and final) gate, lit only when the M9.C
                // distilled-classifier subprocess actually scored chunks
                // — defaults to off in environments without the
                // artifact.
                LiveCountTicker(label: "Voice-passed", value: report.chunksAfterClassifierQuality)
            }
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
            Text(count, format: .number)
                .font(Kiln.Font.body)
                .monospacedDigit()
                .foregroundStyle(count > 0 ? .primary : .tertiary)
        }
    }

    private var skippedFooter: some View {
        Text("\(report.filesSkipped.count, format: .number) files skipped.")
            .font(Kiln.Font.caption)
            .foregroundStyle(.tertiary)
    }

    private var ctaRow: some View {
        HStack(spacing: Kiln.Space.sm) {
            Button("Drop another folder", action: onReset)
            Spacer()
            if let onOpenDeepCuration {
                Button(action: onOpenDeepCuration) {
                    Label("Run Deep Curation", systemImage: "wand.and.stars")
                        .font(Kiln.Font.body)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityHint("Run a Claude Opus Managed Agent over your corpus to remove forwarded threads, copy-pasted external content, and voice-inconsistent samples.")
            }
            Button(action: onContinue) {
                Label("Continue to training", systemImage: "arrow.right")
                    .font(Kiln.Font.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Kiln.Space.m)
                    .padding(.vertical, Kiln.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Kiln.Radius.control, style: .continuous)
                            .fill(Kiln.Palette.firing)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Continue to training")
        }
    }
}
