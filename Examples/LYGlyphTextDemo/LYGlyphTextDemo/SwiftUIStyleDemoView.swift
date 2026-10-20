import LYGlyphText
import SwiftUI

@MainActor
struct SwiftUIStyleDemoView: View {
    @StateObject private var model: StyleDemoModel
    @StateObject private var attachmentState = DemoAttachmentState()
    @State private var replacementProvider: LYGlyphTextAttachmentViewProvider?

    init(samples: StyleDemoSamples) {
        _model = StateObject(wrappedValue: StyleDemoModel(samples: samples))
    }

    init(model: StyleDemoModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Picker("样式", selection: $model.sample) {
                    ForEach(StyleSample.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("styleSampleControl")
                Picker("换行", selection: $model.wrapping) {
                    ForEach(StyleWrapping.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("styleWrappingControl")
                Picker("垂直对齐", selection: $model.verticalAlignment) {
                    ForEach(StyleVerticalAlignment.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("styleVerticalControl")
                Picker("宽度", selection: $model.width) {
                    ForEach([160, 240, 320], id: \.self) { Text("\($0)").tag($0) }
                }
                .accessibilityIdentifier("styleWidthControl")
                Picker("行数", selection: $model.lineLimit) {
                    ForEach(LineLimit.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("styleLineLimitControl")
                Text(model.status).font(.caption).accessibilityIdentifier("styleStatus")
                Text("自然高度").font(.caption).foregroundStyle(.secondary)
                preview(displayHeight: nil)
                    .accessibilityIdentifier("styleNaturalPreview")
                Text("相同内容，展示高度增加 60pt").font(.caption).foregroundStyle(.secondary)
                preview(displayHeight: model.naturalHeight + 60)
                    .accessibilityIdentifier("styleExpandedPreview")
                HStack {
                    Text("按钮点击：\(attachmentState.count)")
                        .accessibilityIdentifier("styleAttachmentCount")
                    Spacer()
                    Button("清空") { model.isCleared = true }
                        .accessibilityIdentifier("styleClear")
                    Button("重新加载") {
                        model.isCleared = false
                        replacementProvider = attachmentState.makeProvider()
                    }
                    .accessibilityIdentifier("styleReload")
                }
                .font(.caption)
            }
            .pickerStyle(.segmented)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func preview(displayHeight: CGFloat?) -> some View {
        LYGlyphTextView(
            document: model.document, configuration: model.configuration,
            viewProvider: replacementProvider ?? attachmentState.provider, displayHeight: displayHeight
        )
        .frame(width: CGFloat(model.width), alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(Rectangle().stroke(Color.gray, lineWidth: 1))
    }
}
