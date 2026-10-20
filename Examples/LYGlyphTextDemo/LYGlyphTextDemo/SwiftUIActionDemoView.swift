import LYGlyphText
import SwiftUI
import UIKit

@MainActor
struct SwiftUIActionDemoView: View {
    let samples: DemoSamples
    @StateObject private var state = ActionDemoState()
    @State private var callbackMode = ActionCallbackMode.a
    @State private var displayMode = 0

    private var configuration: LYGlyphTextConfiguration {
        .init(
            textContainerInset: UIEdgeInsets(top: 14, left: 18, bottom: 14, right: 18),
            numberOfLines: displayMode == 1 ? 8 : 0
        )
    }

    private var callback: (@MainActor (LYGlyphTextActionEvent) -> Void)? {
        guard callbackMode != .none else { return nil }
        let current = callbackMode
        return { event in state.receive(event, callback: current) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("回调", selection: $callbackMode) {
                    ForEach(ActionCallbackMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("actionCallbackControl")
                Picker("展示", selection: $displayMode) {
                    Text("完整").tag(0)
                    Text("截断").tag(1)
                    Text("裁切").tag(2)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("actionDisplayControl")
                Text(state.status)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 34, alignment: .leading)
                    .accessibilityIdentifier("actionEventStatus")
                Text("button=\(state.buttonCount)")
                    .font(.system(size: 12, design: .monospaced))
                    .accessibilityIdentifier("actionButtonStatus")
                LYGlyphTextView(
                    document: samples.actionDocument,
                    configuration: configuration,
                    viewProvider: state.provider,
                    displayHeight: displayMode == 2 ? 60 : nil,
                    onAction: callback
                )
                .frame(width: 330, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
                .overlay(Rectangle().stroke(Color.gray, lineWidth: 1))
                #if DEBUG
                    .overlay {
                        ActionDiagnosticProbe(document: samples.actionDocument)
                            .allowsHitTesting(false)
                    }
                #endif
                Text("向上拖动动作或普通文字可滚动；原生按钮优先处理自己的触摸。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("滚动目标")
                    .foregroundStyle(.secondary)
                    .frame(height: 360, alignment: .top)
                    .accessibilityIdentifier("actionScrollMarker")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
