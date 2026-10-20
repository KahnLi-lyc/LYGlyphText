import LYGlyphText
import SwiftUI

@MainActor
struct SwiftUIDemoView: View {
    let samples: DemoSamples
    @State private var selectedSample = SampleKind.short
    @State private var selectedWidth = 240
    @State private var selectedLineLimit = LineLimit.unlimited

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
                Picker("行数", selection: $selectedLineLimit) {
                    ForEach(LineLimit.allCases, id: \.rawValue) { limit in
                        Text(limit.title).tag(limit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("lineLimitControl")
                Text("\(selectedSample.title) · 宽度 \(selectedWidth) · \(selectedLineLimit.title)")
                    .font(.caption)
                    .accessibilityIdentifier("sampleStatus")
                LYGlyphTextView(
                    document: samples.documents[selectedSample],
                    configuration: .init(
                        textContainerInset: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10),
                        numberOfLines: selectedLineLimit.rawValue
                    )
                )
                .frame(width: CGFloat(selectedWidth), alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .overlay(Rectangle().stroke(Color.gray, lineWidth: 1))
                .accessibilityIdentifier("richTextPreview")
                Text("展示宽度直接传入 UIViewRepresentable 的测量流程。限制行数后，溢出内容在最后一行尾部省略。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
