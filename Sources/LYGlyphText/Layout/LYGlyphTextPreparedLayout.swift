import UIKit

/// 在主线程之外完成 Core Text 排版的结果；列表数据到达时可预先得到行高，再交给展示相同输入的 Label 复用。
///
/// 结果只对创建时的文档对象、配置、宽度和显示环境有效。`LYGlyphTextLabel.apply(_:)` 会设置文档与配置；
/// 显示环境（字号类别、明暗、显示比例等）不一致时不复用，Label 按普通路径重新排版。
@MainActor
public final class LYGlyphTextPreparedLayout {
    /// 包含内边距的展示尺寸，单位 point，已按显示比例向上对齐像素；可直接作为列表行高的文字部分。
    public let size: CGSize
    /// 创建时使用的文档。
    public let document: LYGlyphTextDocument?
    /// 创建时使用的配置。
    public let configuration: LYGlyphTextConfiguration

    let width: CGFloat?
    let environment: LayoutEnvironment
    let resolvedText: ResolvedText
    let layout: LYGlyphTextLayout
    /// 诊断：排版是否在主线程完成。
    let wasBuiltOnMainThread: Bool

    private init(
        document: LYGlyphTextDocument?, configuration: LYGlyphTextConfiguration, width: CGFloat?,
        environment: LayoutEnvironment, built: Built
    ) {
        self.document = document
        self.configuration = configuration
        self.width = width
        self.environment = environment
        resolvedText = built.text
        layout = built.layout
        wasBuiltOnMainThread = built.wasOnMainThread
        size = built.layout.size
    }

    /// 在后台线程排版，不创建视图、不调用附件工厂或加载网络图片。
    /// - Parameters:
    ///   - document: 要排版的文档；nil 得到只含内边距的尺寸。
    ///   - configuration: 显示配置，包括内边距、行数和截断 token。
    ///   - width: 包含内边距的展示宽度，单位 point；非有限值按理想宽度（不强制软换行）处理，负值按 0。
    ///   - traitCollection: 决定动态字体、动态颜色和显示比例，通常传入将要展示的宿主 traitCollection。
    public static func prepare(
        document: LYGlyphTextDocument?, configuration: LYGlyphTextConfiguration = .init(), width: CGFloat,
        traitCollection: UITraitCollection
    ) async -> LYGlyphTextPreparedLayout {
        let normalized: CGFloat? = width.isFinite ? max(0, width) : nil
        let built = await withCheckedContinuation { (continuation: CheckedContinuation<Built, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Built(
                    document: document, configuration: configuration, width: normalized, traits: traitCollection
                ))
            }
        }
        return LYGlyphTextPreparedLayout(
            document: document, configuration: configuration, width: normalized,
            environment: LayoutEnvironment(traitCollection), built: built
        )
    }

    /// 后台构造的排版结果；只在创建它的线程与随后接收它的 MainActor 之间转移一次。
    struct Built {
        let text: ResolvedText
        let layout: LYGlyphTextLayout
        let wasOnMainThread: Bool

        init(
            document: LYGlyphTextDocument?, configuration: LYGlyphTextConfiguration, width: CGFloat?,
            traits: UITraitCollection
        ) {
            text = ResolvedText(document: document, traits: traits, wrapping: configuration.wrapping)
            layout = text.layout(
                width: width, insets: configuration.insets,
                scale: traits.displayScale > 0 ? traits.displayScale : 1,
                numberOfLines: max(0, configuration.numberOfLines), truncationToken: configuration.truncationToken
            )
            wasOnMainThread = Thread.isMainThread
        }
    }
}

/// 影响字体解析、动态颜色和像素对齐的显示环境；用于判断预排版结果能否复用。
struct LayoutEnvironment: Equatable {
    let contentSizeCategory: UIContentSizeCategory
    let userInterfaceStyle: UIUserInterfaceStyle
    let displayScale: CGFloat
    let accessibilityContrast: UIAccessibilityContrast
    let legibilityWeight: UILegibilityWeight
    let userInterfaceLevel: UIUserInterfaceLevel
    let layoutDirection: UITraitEnvironmentLayoutDirection

    init(_ traits: UITraitCollection) {
        contentSizeCategory = traits.preferredContentSizeCategory
        userInterfaceStyle = traits.userInterfaceStyle
        displayScale = traits.displayScale > 0 ? traits.displayScale : 1
        accessibilityContrast = traits.accessibilityContrast
        legibilityWeight = traits.legibilityWeight
        userInterfaceLevel = traits.userInterfaceLevel
        layoutDirection = traits.layoutDirection
    }
}
