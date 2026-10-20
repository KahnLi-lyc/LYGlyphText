import SwiftUI
import UIKit

@main
@MainActor
final class DemoAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Demo", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = DemoSceneDelegate.self
        return configuration
    }
}

@MainActor
final class DemoHomeController: UITableViewController {
    private let samples: DemoSamples

    init(samples: DemoSamples) {
        self.samples = samples
        super.init(style: .insetGrouped)
        title = "LYGlyphText"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("请使用 init(samples:)")
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        8
    }

    override func tableView(_: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = [
            "UIKit 示例", "SwiftUI 示例", "UIView 列表复用", "UIKit 样式与垂直对齐", "SwiftUI 样式与垂直对齐",
            "UIKit 文字交互", "SwiftUI 文字交互", "文字交互与列表选择"
        ][indexPath.row]
        cell.detailTextLabel?.text = "切换文本、宽度，查看富文本自动撑高"
        cell
            .accessibilityIdentifier = [
                "openUIKit",
                "openSwiftUI",
                "openReuse",
                "openUIKitStyles",
                "openSwiftUIStyles",
                "openUIKitActions",
                "openSwiftUIActions",
                "openActionList"
            ][indexPath.row]
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let controller: UIViewController
        if indexPath.row == 0 {
            controller = UIKitDemoController(samples: samples)
        } else if indexPath.row == 2 {
            controller = ReuseDemoController(documents: samples.reuseDocuments)
        } else if indexPath.row == 3 {
            controller = UIKitStyleDemoController(samples: samples.styles)
        } else if indexPath.row == 4 {
            controller = UIHostingController(rootView: SwiftUIStyleDemoView(samples: samples.styles))
            controller.title = "SwiftUI 样式"
        } else if indexPath.row == 5 {
            controller = UIKitActionDemoController(samples: samples)
        } else if indexPath.row == 6 {
            controller = UIHostingController(rootView: SwiftUIActionDemoView(samples: samples))
            controller.title = "SwiftUI 文字交互"
        } else if indexPath.row == 7 {
            controller = ActionSelectionDemoController(documents: samples.actionListDocuments)
        } else {
            controller = UIHostingController(rootView: SwiftUIDemoView(samples: samples))
            controller.title = "SwiftUI"
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}
