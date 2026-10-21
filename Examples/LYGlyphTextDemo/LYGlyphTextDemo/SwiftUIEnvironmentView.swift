import LYGlyphText
import SwiftUI

@MainActor
struct SwiftUIEnvironmentView: View {
    let samples: EnvironmentSamples
    @State private var selection = EnvironmentSelection()
    @StateObject private var state = EnvironmentEventState()

    init(samples: EnvironmentSamples, selection: EnvironmentSelection = .init()) {
        self.samples = samples
        _selection = State(initialValue: selection)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Picker("字号", selection: $selection.sizeIndex) {
                    Text("L").tag(0)
                    Text("XXXL").tag(1)
                    Text("AX5").tag(2)
                }.accessibilityIdentifier("environmentSize")
                Picker("外观", selection: $selection.isDark) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }.accessibilityIdentifier("environmentScheme")
                Picker("方向", selection: $selection.isRTL) {
                    Text("LTR").tag(false)
                    Text("RTL").tag(true)
                }.accessibilityIdentifier("environmentDirection")
                Picker("宽度", selection: $selection.width) {
                    Text("160").tag(160)
                    Text("320").tag(320)
                }.accessibilityIdentifier("environmentWidth")
                Picker("行数", selection: $selection.isSingleLine) {
                    Text("1").tag(true)
                    Text("不限").tag(false)
                }.accessibilityIdentifier("environmentLines")
                Picker("回调", selection: $selection.callback) {
                    Text("A").tag("A")
                    Text("B").tag("B")
                }.accessibilityIdentifier("environmentCallback")
                Text(selection.status)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("environmentSelection")
                Text(state.status)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("environmentEvents")
                preview
            }
            .pickerStyle(.segmented)
            .padding(16)
        }
        .accessibilityIdentifier("environmentScroll")
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(selection.isDark ? .dark : .light)
        // UIKit 导航不是 SwiftUI 呈现边界；偏好之外仍需向内容子树传递实际环境。
        .environment(\.colorScheme, selection.isDark ? .dark : .light)
        .navigationTitle("SwiftUI 环境与无障碍")
        .toolbarColorScheme(selection.isDark ? .dark : .light, for: .navigationBar)
        .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var preview: some View {
        let callback = selection.callback
        return LYGlyphTextView(
            document: samples.document, configuration: selection.configuration, viewProvider: state.provider,
            onAction: { event in state.receive(event, callback: callback) }
        )
        .frame(width: CGFloat(selection.width))
        .dynamicTypeSize(selection.dynamicSize)
        .environment(\.layoutDirection, selection.isRTL ? .rightToLeft : .leftToRight)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}
