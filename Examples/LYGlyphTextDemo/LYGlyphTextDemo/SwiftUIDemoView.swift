import LYGlyphText
import SwiftUI

@MainActor
struct SwiftUIDemoView: View {
    let samples: DemoSamples
    @State private var selectedSample = SampleKind.short
    @State private var selectedWidth = 240
    @State private var selectedLineLimit = LineLimit.unlimited
    @State private var contentMode = 0
    @State private var isCleared = false
    @State private var replacementProvider: LYGlyphTextAttachmentViewProvider?
    @StateObject private var attachmentState = DemoAttachmentState()
    @State private var imageAlignment = ImageAlignment.bottom

    private var status: String {
        let imageStatus = contentMode == 2 ? " · UIView · \(imageAlignment.title)" :
            (contentMode == 1 ? " · 图片混排 · \(imageAlignment.title)" : "")
        return "\(selectedSample.title) · 宽度 \(selectedWidth) · \(selectedLineLimit.title)\(imageStatus)"
    }

    private var activeDocument: LYGlyphTextDocument? {
        guard !isCleared else { return nil }
        return contentMode == 2
            ? samples.viewDocument(for: selectedSample, alignment: imageAlignment)
            : samples.document(for: selectedSample, includesImages: contentMode == 1, alignment: imageAlignment)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("文本", selection: $selectedSample) {
                    ForEach(SampleKind.allCases, id: \.rawValue) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("sampleControl")
                Picker("内容", selection: $contentMode) {
                    Text("文字").tag(0)
                    Text("图片混排").tag(1)
                    Text("UIView").tag(2)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("imageControl")
                Picker("图片对齐", selection: $imageAlignment) {
                    ForEach(ImageAlignment.allCases, id: \.rawValue) { alignment in
                        Text(alignment.title).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(contentMode == 0)
                .accessibilityIdentifier("alignmentControl")
                Picker("宽度", selection: $selectedWidth) {
                    ForEach([160, 240, 320], id: \.self) { width in
                        Text("\(width)").tag(width)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("widthControl")
                Picker("行数", selection: $selectedLineLimit) {
                    ForEach(LineLimit.allCases, id: \.rawValue) { limit in
                        Text(limit.title).tag(limit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("lineLimitControl")
                Text(status)
                    .font(.caption)
                    .accessibilityIdentifier("sampleStatus")
                LYGlyphTextView(
                    document: activeDocument,
                    configuration: .init(
                        textContainerInset: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10),
                        numberOfLines: selectedLineLimit.rawValue
                    ),
                    viewProvider: replacementProvider ?? attachmentState.provider
                )
                .frame(width: CGFloat(selectedWidth), alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .overlay(Rectangle().stroke(Color.gray, lineWidth: 1))
                .accessibilityIdentifier("richTextPreview")
                Text("按钮点击：\(attachmentState.count)")
                    .font(.caption)
                    .accessibilityIdentifier("attachmentCount")
                HStack {
                    Button("清空") { isCleared = true }
                        .accessibilityIdentifier("clearAttachments")
                    Button("重新加载") {
                        isCleared = false
                        replacementProvider = attachmentState.makeProvider()
                    }
                    .accessibilityIdentifier("reloadAttachments")
                }
                Text("图片：上向箭头橙标在左上，右向箭头橙标在右上；对齐参照当前字体区域。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("展示宽度直接传入 UIViewRepresentable 的测量流程。限制行数后，溢出内容在最后一行尾部省略。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
