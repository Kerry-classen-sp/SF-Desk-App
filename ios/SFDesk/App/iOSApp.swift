#if os(iOS)
import SafariServices
import UIKit
import WebKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ app: UIApplication, configurationForConnecting session: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let config = UISceneConfiguration(name: nil, sessionRole: session.role)
    config.delegateClass = SceneDelegate.self
    return config
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    window = UIWindow(windowScene: scene)
    window!.rootViewController = MainViewController()
    window!.makeKeyAndVisible()
  }
}

final class MainViewController: UIViewController, HostUI {
  private var controller: AppController!
  private var page: WKWebView?
  private var signInSheet: UIViewController?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let res = Bundle.main.resourceURL!
    let data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SF Desk")
    let info = Bundle.main.infoDictionary ?? [:]
    let config = AppController.Config(
      webRoot: res.appendingPathComponent("web"), coreBundle: res.appendingPathComponent("core-bundle.js"),
      database: data.appendingPathComponent("sf-desk.db"),
      loginUrl: info["SFDeskLoginURL"] as? String ?? "https://login.salesforce.com",
      version: "\(info["CFBundleShortVersionString"] ?? "0") (\(info["CFBundleVersion"] ?? "0"))")
    do {
      controller = try AppController(config: config, ui: self)
      controller.start()
    } catch {
      let label = UILabel()
      label.numberOfLines = 0
      label.text = "SF Desk couldn't start: \(error.localizedDescription)"
      label.frame = view.bounds.insetBy(dx: 24, dy: 80)
      view.addSubview(label)
    }
  }

  // The topmost screen, for alerts and sheets while the sign-in sheet is up.
  private var top: UIViewController {
    var vc: UIViewController = self
    while let next = vc.presentedViewController { vc = next }
    return vc
  }

  func show(page web: WKWebView) {
    if let sheet = signInSheet {
      signInSheet = nil
      sheet.dismiss(animated: true)
    }
    guard page !== web else { return }
    page?.removeFromSuperview()
    page = web
    web.translatesAutoresizingMaskIntoConstraints = false
    web.scrollView.contentInsetAdjustmentBehavior = .automatic
    // Pulling down reloads the view showing (the page's Refresh), until it has loaded.
    let pull = UIRefreshControl()
    pull.addTarget(self, action: #selector(pulledToRefresh(_:)), for: .valueChanged)
    web.scrollView.refreshControl = pull
    web.scrollView.alwaysBounceVertical = true
    view.addSubview(web)
    NSLayoutConstraint.activate([
      web.leadingAnchor.constraint(equalTo: view.leadingAnchor), web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  @objc private func pulledToRefresh(_ pull: UIRefreshControl) {
    guard let page else { return pull.endRefreshing() }
    page.callAsyncJavaScript("if (window.sfdeskRefresh) await window.sfdeskRefresh();", arguments: [:], in: nil, in: .page) { _ in
      pull.endRefreshing()
    }
  }

  func show(signIn web: WKWebView, cancel: @escaping () -> Void) {
    let vc = SignInViewController(web: web, cancel: { [weak self] in
      self?.signInSheet = nil
      cancel()
    })
    let nav = UINavigationController(rootViewController: vc)
    nav.presentationController?.delegate = vc
    signInSheet = nav
    top.present(nav, animated: true)
  }

  func confirm(_ message: String, done: @escaping (Bool) -> Void) {
    let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(false) })
    a.addAction(UIAlertAction(title: "OK", style: .default) { _ in done(true) })
    top.present(a, animated: true)
  }

  func alert(_ message: String, done: @escaping () -> Void) {
    let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    a.addAction(UIAlertAction(title: "OK", style: .default) { _ in done() })
    top.present(a, animated: true)
  }

  func prompt(_ message: String, defaultText: String?, done: @escaping (String?) -> Void) {
    let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    a.addTextField { $0.text = defaultText }
    a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done(nil) })
    a.addAction(UIAlertAction(title: "OK", style: .default) { _ in done(a.textFields?.first?.text) })
    top.present(a, animated: true)
  }

  // Excel exports: the share sheet (Save to Files, Mail, Teams...).
  func share(file: URL) {
    let vc = UIActivityViewController(activityItems: [file], applicationActivities: nil)
    vc.popoverPresentationController?.sourceView = view
    vc.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
    top.present(vc, animated: true)
  }

  // Salesforce links open the Salesforce app when it's installed (universal links), otherwise Safari.
  func open(external url: URL) {
    guard url.scheme == "https" || url.scheme == "http" else { return UIApplication.shared.open(url) }
    UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
      if !opened { self.top.present(SFSafariViewController(url: url), animated: true) }
    }
  }
}

private final class SignInViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
  private let web: WKWebView
  private let cancel: () -> Void

  init(web: WKWebView, cancel: @escaping () -> Void) {
    self.web = web
    self.cancel = cancel
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }

  override func loadView() { view = web }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Sign in to Salesforce"
    navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
      self?.dismiss(animated: true)
      self?.cancel()
    })
  }

  func presentationControllerDidDismiss(_ controller: UIPresentationController) { cancel() }
}
#endif
