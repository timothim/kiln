import SwiftUI

struct ContentView: View {
    private var appVersion: String {
        let dict = Bundle.main.infoDictionary
        let short = dict?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = dict?["CFBundleVersion"] as? String ?? "0"
        return "v\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Kiln")
                .font(.system(size: 48, weight: .semibold, design: .default))
            Text("Drop a folder. Meet yourself.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(appVersion)
                .font(.footnote.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    ContentView()
}
