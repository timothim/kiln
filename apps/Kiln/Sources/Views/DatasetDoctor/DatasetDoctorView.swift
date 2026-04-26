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
        VStack(alignment: .leading, spacing: Kiln.Space.s7) {
            doctorHeader
            funnelRow
            qualitySection
            if report.filesSkipped.count > 0 {
                skippedFooter
            }
            Spacer(minLength: 0)
            finalCard
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Kiln.Palette.paper)
        .sheet(isPresented: deepCurationIsPresented) {
            if let model = deepCurationModel {
                DeepCurationSheet(
                    model: model,
                    onClose: { onCloseDeepCuration?() }
                )
            }
        }
    }

    /// Per the design's `pipeline` surface (`proto-surfaces.js:238-243`):
    /// serif `Dataset Doctor` h1 + `chip.firing` with pulse + `path-chip`
    /// for the source folder.
    private var doctorHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.s3) {
            Text("Dataset Doctor")
                .font(.system(size: 28, weight: .medium, design: .serif))
                .foregroundStyle(Kiln.Palette.onSurface)
            Chip(text: "Done", isFiring: true)
            if let folder = project.folderName {
                Text("~/\(folder)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Kiln.Palette.onSurface3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        Capsule(style: .continuous)
                            .fill(Kiln.Palette.surface2)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Kiln.Palette.hairline, lineWidth: 0.5)
                    }
            }
            Spacer(minLength: 0)
        }
    }

    /// Final summary card per `proto-surfaces.js:278-283` + `.s-pipeline
    /// .final` CSS — `surface` fill, `firing-line` border, big serif numeric,
    /// "of N chunks ready · X%", spacer, primary Continue button.
    private var finalCard: some View {
        let kept = classifierGateActive
            ? report.chunksAfterClassifierQuality
            : report.chunksAfterQuality
        let total = report.chunksBeforeDedup
        let pct = total > 0 ? Int((Double(kept) / Double(total)) * 100) : 0

        return HStack(alignment: .firstTextBaseline, spacing: Kiln.Space.s4) {
            Text(kept, format: .number)
                .font(.system(size: 36, weight: .medium, design: .serif))
                .foregroundStyle(Kiln.Palette.firing2)
                .monospacedDigit()
            Text("of ")
                .font(Kiln.Font.label)
                .foregroundStyle(Kiln.Palette.onSurface2)
            + Text(total, format: .number)
                .font(Kiln.Font.label)
                .foregroundStyle(Kiln.Palette.onSurface2)
                .monospacedDigit()
            + Text(" chunks ready · ")
                .font(Kiln.Font.label)
                .foregroundStyle(Kiln.Palette.onSurface2)
            + Text("\(pct)%")
                .font(Kiln.Font.label.weight(.medium))
                .foregroundStyle(Kiln.Palette.onSurface)
            Spacer()
            HStack(spacing: Kiln.Space.s3) {
                Button("Drop another folder", action: onReset)
                    .buttonStyle(.bordered)
                if let onOpenDeepCuration {
                    Button("Run Deep Curation", action: onOpenDeepCuration)
                        .buttonStyle(.bordered)
                }
                Button(action: onContinue) {
                    Text("Continue")
                        .font(Kiln.Font.label.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Kiln.Space.s4)
                        .padding(.vertical, Kiln.Space.s2)
                        .background {
                            RoundedRectangle(cornerRadius: Kiln.Radius.rSm,
                                             style: .continuous)
                                .fill(Kiln.Palette.firing)
                        }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Continue to training")
            }
        }
        .padding(.horizontal, Kiln.Space.s6)
        .padding(.vertical, Kiln.Space.s5)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Kiln.Radius.rLg, style: .continuous)
                .fill(Kiln.Palette.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Kiln.Radius.rLg, style: .continuous)
                .strokeBorder(Kiln.Palette.firingLine, lineWidth: 1)
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

}
