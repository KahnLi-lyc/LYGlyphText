import UIKit

@MainActor
final class DemoSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options _: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        do {
            if ProcessInfo.processInfo.arguments.contains("--performance-profile") {
                window.rootViewController = try UINavigationController(
                    rootViewController: PerformanceListController(profile: true)
                )
            } else {
                try window.rootViewController = UINavigationController(
                    rootViewController: DemoHomeController(samples: DemoSamples())
                )
            }
        } catch {
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            let label = UILabel()
            label.text = "无法构建演示文档：\(error)"
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(
                    equalTo: controller.view.safeAreaLayoutGuide.leadingAnchor,
                    constant: 20
                ),
                label.trailingAnchor.constraint(
                    equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor,
                    constant: -20
                ),
                label.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 20)
            ])
            window.rootViewController = controller
        }
        window.makeKeyAndVisible()
        self.window = window
    }
}
