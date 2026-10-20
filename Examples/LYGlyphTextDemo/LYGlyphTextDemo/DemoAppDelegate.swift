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
        2
    }

    override func tableView(_: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = indexPath.row == 0 ? "UIKit 示例" : "SwiftUI 示例"
        cell.detailTextLabel?.text = "切换文本、宽度，查看富文本自动撑高"
        cell.accessibilityIdentifier = indexPath.row == 0 ? "openUIKit" : "openSwiftUI"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let controller: UIViewController
        if indexPath.row == 0 {
            controller = UIKitDemoController(samples: samples)
        } else {
            controller = UIHostingController(rootView: SwiftUIDemoView(samples: samples))
            controller.title = "SwiftUI"
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}
