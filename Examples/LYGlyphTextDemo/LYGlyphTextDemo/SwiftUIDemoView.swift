import LYGlyphText
import SwiftUI

@MainActor
struct SwiftUIDemoView: View {
    let samples: DemoSamples
    @State private var selectedSample = SampleKind.short
    @State private var selectedWidth = 240
    @State private var selectedLineLimit = LineLimit.unlimited
    @State private var includesImages = false
    @State private var imageAlignment = ImageAlignment.bottom

    private var status: String {
        let imageStatus = includesImages ? " · 图片混排 · \(imageAlignment.title)" : ""
        return "\(selectedSample.title) · 宽度 \(selectedWidth) · \(selectedLineLimit.title)\(imageStatus)"
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
                Picker("内容", selection: $includesImages) {
                    Text("文字").tag(false)
                    Text("图片混排").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("imageControl")
                Picker("图片对齐", selection: $imageAlignment) {
                    ForEach(ImageAlignment.allCases, id: \.rawValue) { alignment in
                        Text(alignment.title).tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!includesImages)
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
                    document: samples.document(
                        for: selectedSample, includesImages: includesImages, alignment: imageAlignment
                    ),
                    configuration: .init(
                        textContainerInset: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10),
                        numberOfLines: selectedLineLimit.rawValue
                    )
                )
                .frame(width: CGFloat(selectedWidth), alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .overlay(Rectangle().stroke(Color.gray, lineWidth: 1))
                .accessibilityIdentifier("richTextPreview")
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
