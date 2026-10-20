import LYGlyphText
import SwiftUI

@MainActor
struct SwiftUIDemoView: View {
    let samples: DemoSamples
    @State private var selectedSample = SampleKind.short
    @State private var selectedWidth = 240

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
                Picker("宽度", selection: $selectedWidth) {
                    ForEach([160, 240, 320], id: \.self) { width in
                        Text("\(width)").tag(width)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("widthControl")
                Text("\(selectedSample.title) · 宽度 \(selectedWidth)")
                    .font(.caption)
                    .accessibilityIdentifier("sampleStatus")
                LYGlyphTextView(
                    document: samples.documents[selectedSample],
                    configuration: .init(textContainerInset: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
                )
                .frame(width: CGFloat(selectedWidth))
                .background(Color(uiColor: .secondarySystemBackground))
                .overlay(Rectangle().stroke(Color.gray, lineWidth: 1))
                .accessibilityIdentifier("richTextPreview")
                Text("展示宽度直接传入 UIViewRepresentable 的测量流程，两端使用相同文档和内边距。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
