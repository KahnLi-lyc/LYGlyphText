import LYGlyphText
import SwiftUI

@MainActor
struct SwiftUIHostMatrixView: View {
    enum Container: String, CaseIterable, Identifiable {
        case frame = "Frame"
        case hStack = "HStack"
        case vStack = "VStack"
        case list = "List"
        case lazy = "LazyVStack"

        var id: String {
            rawValue
        }
    }

    let samples: HostMatrixSamples
    @StateObject private var rowZeroState: HostMatrixRowState
    @State private var rowStates: [Int: HostMatrixRowState] = [:]
    @State private var content = HostMatrixContent.action
    @State private var widthIndex = 1
    @State private var container = Container.frame
    @State private var callback = HostMatrixCallback.a
    @State private var naturalHeight: CGFloat = 0

    init(samples: HostMatrixSamples) {
        self.samples = samples
        let states = Dictionary(uniqueKeysWithValues: samples.rows.map {
            ($0.id, HostMatrixRowState(rowID: $0.id))
        })
        _rowZeroState = StateObject(wrappedValue: states[samples.rows[0].id]!)
        _rowStates = State(initialValue: states)
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("内容", selection: $content) {
                ForEach(HostMatrixContent.allCases, id: \.self) { value in
                    Text(contentName(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("hostSwiftUIContent")
            Picker("宽度", selection: $widthIndex) {
                ForEach(Array(widthNames.enumerated()), id: \.offset) { index, name in
                    Text(name).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("hostSwiftUIWidth")
            Picker("容器", selection: $container) {
                ForEach(Container.allCases) { value in Text(value.rawValue).tag(value) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("hostSwiftUIContainer")
            Picker("回调", selection: $callback) {
                Text("A").tag(HostMatrixCallback.a)
                Text("B").tag(HostMatrixCallback.b)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("hostSwiftUICallback")

            Group {
                if container == .list {
                    List(samples.rows) { row in rowView(row) }
                        .accessibilityIdentifier("hostSwiftUIList")
                } else if container == .lazy {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(samples.rows) { row in rowView(row) }
                        }
                    }
                    .accessibilityIdentifier("hostSwiftUILazy")
                } else {
                    preview
                }
            }
            .frame(maxHeight: .infinity)

            Text("row=0;content=\(content.rawValue);width=\(widthNames[widthIndex])")
                .font(.system(.caption, design: .monospaced))
                .accessibilityIdentifier("hostSwiftUICurrentRow")
            Text(String(format: "natural=%.1f", Double(naturalHeight)))
                .font(.system(.caption, design: .monospaced))
                .accessibilityIdentifier("hostSwiftUINaturalHeight")
            Text(
                "event=\(rowZeroState.actionCount);" +
                    "callback=\(rowZeroState.callback.rawValue);" +
                    "handled=\(rowZeroState.lastHandledCallback?.rawValue ?? "none");" +
                    "id=\(rowZeroState.lastActionID ?? "none")"
            )
            .font(.system(.caption, design: .monospaced))
            .accessibilityIdentifier("hostSwiftUIEvent")
            Text("button=\(rowZeroState.buttonCount)")
                .font(.system(.caption, design: .monospaced))
                .accessibilityIdentifier("hostSwiftUIButtonStatus")
        }
        .padding(12)
        .navigationTitle("SwiftUI 宿主矩阵")
        .onChange(of: callback) { value in
            rowStates.values.forEach { $0.selectCallback(value) }
        }
        .onPreferenceChange(HostNaturalHeightPreferenceKey.self) { naturalHeight = $0 }
    }

    @ViewBuilder
    private var preview: some View {
        #if DEBUG
            previewContent.overlay {
                GeometryReader { proxy in
                    HostContainerGeometryProbe(
                        container: container.rawValue,
                        geometry: proxy.frame(in: .local)
                    )
                    .allowsHitTesting(false)
                }
            }
        #else
            previewContent
        #endif
    }

    private var previewContent: some View {
        Group {
            let text = glyphView(row: samples.rows[0], state: rowZeroState)
            switch container {
            case .frame:
                text.frame(width: selectedWidth).background(Color(uiColor: .secondarySystemGroupedBackground))
            case .hStack:
                HStack(spacing: 0) {
                    Color.clear.frame(width: 20)
                    text.frame(width: selectedWidth)
                }
            case .vStack:
                VStack(spacing: 0) {
                    text.frame(width: selectedWidth)
                    Color.clear.frame(width: selectedWidth, height: 8)
                }
            case .list, .lazy:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func glyphView(row: HostMatrixRow, state: HostMatrixRowState) -> some View {
        if let document = row.documents[content] {
            LYGlyphTextView(
                document: document,
                configuration: .init(textContainerInset: .init(top: 8, left: 8, bottom: 8, right: 8)),
                viewProvider: state.provider,
                onAction: { event in
                    state.receive(event)
                }
            )
            .accessibilityIdentifier("hostSwiftUIGlyph\(row.id)")
            .overlay {
                #if DEBUG
                    if content == .action {
                        ActionDiagnosticProbe(
                            document: document,
                            identifier: "hostSwiftUIAction\(row.id)"
                        )
                    } else if content == .smallView || content == .largeView {
                        HostAttachmentIdentifierProbe(
                            document: document, identifier: "hostSwiftUIAttachmentButton\(row.id)"
                        )
                    }
                #endif
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: HostNaturalHeightPreferenceKey.self, value: proxy.size.height)
                }
            }
        }
    }

    private func rowView(_ row: HostMatrixRow) -> some View {
        let state = state(for: row.id)
        return VStack(alignment: .leading, spacing: 4) {
            glyphView(row: row, state: state)
            RowStatus(state: state)
        }
        .frame(width: selectedWidth)
        .id(row.id)
    }

    private func state(for rowID: Int) -> HostMatrixRowState {
        rowStates[rowID] ?? rowZeroState
    }

    private var selectedWidth: CGFloat? {
        [CGFloat?(160), 240, 320, nil][widthIndex]
    }

    private var widthNames: [String] {
        ["160", "240", "320", "容器"]
    }

    private func contentName(_ content: HostMatrixContent) -> String {
        ["短", "长", "小图", "大图", "小视", "大视", "动作"][content.rawValue]
    }

    private struct RowStatus: View {
        @ObservedObject var state: HostMatrixRowState

        var body: some View {
            Text(
                "row=\(state.rowID);event=\(state.actionCount);button=\(state.buttonCount);" +
                    "callback=\(state.callback.rawValue);" +
                    "handled=\(state.lastHandledCallback?.rawValue ?? "none");" +
                    "id=\(state.lastActionID ?? "none")"
            )
            .font(.system(.caption2, design: .monospaced))
            .accessibilityIdentifier("hostSwiftUIRowStatus\(state.rowID)")
        }
    }
}

private struct HostNaturalHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if DEBUG
    @MainActor
    private struct HostContainerGeometryProbe: UIViewRepresentable {
        let container: String
        let geometry: CGRect

        func makeUIView(context _: Context) -> HostContainerGeometryView {
            HostContainerGeometryView(container: container, geometry: geometry)
        }

        func updateUIView(_ uiView: HostContainerGeometryView, context _: Context) {
            uiView.update(container: container, geometry: geometry)
        }
    }

    @MainActor
    private final class HostContainerGeometryView: UIView {
        init(container: String, geometry: CGRect) {
            super.init(frame: .zero)
            isAccessibilityElement = true
            accessibilityIdentifier = "hostSwiftUIContainerGeometry"
            isUserInteractionEnabled = false
            backgroundColor = .clear
            update(container: container, geometry: geometry)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("请使用 init(container:geometry:)")
        }

        func update(container: String, geometry: CGRect) {
            accessibilityValue = String(
                format: "container=%@;x=%.1f;y=%.1f;width=%.1f;height=%.1f",
                container,
                Double(geometry.minX), Double(geometry.minY),
                Double(geometry.width), Double(geometry.height)
            )
        }
    }

    @MainActor
    private struct HostAttachmentIdentifierProbe: UIViewRepresentable {
        let document: LYGlyphTextDocument
        let identifier: String

        func makeUIView(context _: Context) -> HostAttachmentIdentifierView {
            HostAttachmentIdentifierView(document: document, identifier: identifier)
        }

        func updateUIView(_ uiView: HostAttachmentIdentifierView, context _: Context) {
            uiView.document = document
            uiView.identifier = identifier
            uiView.refresh()
        }
    }

    @MainActor
    private final class HostAttachmentIdentifierView: UIView {
        var document: LYGlyphTextDocument
        var identifier: String

        init(document: LYGlyphTextDocument, identifier: String) {
            self.document = document
            self.identifier = identifier
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("请使用 init(document:identifier:)")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            refresh()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            refresh()
        }

        func refresh() {
            Task { @MainActor [weak self] in
                guard let self, let label = findLabel(in: window), let button = findButton(in: label) else { return }
                button.accessibilityIdentifier = identifier
            }
        }

        private func findLabel(in view: UIView?) -> LYGlyphTextLabel? {
            guard let view else { return nil }
            if let label = view as? LYGlyphTextLabel, label.document === document { return label }
            return view.subviews.lazy.compactMap(findLabel).first
        }

        private func findButton(in view: UIView) -> UIButton? {
            if let button = view as? UIButton { return button }
            return view.subviews.lazy.compactMap(findButton).first
        }
    }
#endif
