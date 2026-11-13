import UIKit

/// 全屏播放时允许横屏，其它页面保持竖屏。
enum OrientationManager {
    static var allowLandscape = false
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        LibraryStore.shared.prepare()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = Theme.background
        window.tintColor = Theme.red
        window.rootViewController = UINavigationController(rootViewController: HomeViewController())
        window.makeKeyAndVisible()
        self.window = window

        if let url = launchOptions?[.url] as? URL {
            DispatchQueue.main.async { [weak self] in
                _ = self?.handleIncomingFile(url)
            }
        }
        return true
    }

    /// 支持从「文件」App 通过"共享 / 在…中打开"直接导入 SWF。
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return handleIncomingFile(url)
    }

    @discardableResult
    private func handleIncomingFile(_ url: URL) -> Bool {
        do {
            let item = try LibraryStore.shared.importFile(from: url)
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let navigation = self.window?.rootViewController as? UINavigationController else { return }
                navigation.dismiss(animated: false)
                navigation.popToRootViewController(animated: false)
                (navigation.viewControllers.first as? HomeViewController)?.open(item: item)
            }
            return true
        } catch {
            DispatchQueue.main.async { [weak self] in
                let message = (error as? LocalizedError)?.errorDescription ?? L("home.importErrorGeneric")
                let alert = UIAlertController(title: L("home.importErrorTitle"),
                                              message: message,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
                self?.window?.rootViewController?.present(alert, animated: true)
            }
            return false
        }
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return OrientationManager.allowLandscape ? .allButUpsideDown : .portrait
    }
}
