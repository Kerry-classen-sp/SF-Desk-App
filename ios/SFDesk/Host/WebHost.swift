import Foundation
import UniformTypeIdentifiers
import WebKit

// What the app's window does for the host: iOS (App/iOSApp.swift) or the Mac test build (App/MacTestApp.swift).
protocol HostUI: AnyObject {
  func show(page: WKWebView)
  func show(signIn: WKWebView, cancel: @escaping () -> Void)
  func confirm(_ message: String, done: @escaping (Bool) -> Void)
  func alert(_ message: String, done: @escaping () -> Void)
  func prompt(_ message: String, defaultText: String?, done: @escaping (String?) -> Void)
  func share(file: URL)
  func open(external url: URL)
}

// The page (public/, copied to Generated/web) at sfdesk://app/, as the desktop server serves it: files, and
// /api/* answered by the shared core in JavaScriptCore. Opening /login signs in to Salesforce.
final class AppController: NSObject, WKURLSchemeHandler, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
  static let scheme = "sfdesk"
  static let home = URL(string: "sfdesk://app/")!

  struct Config {
    var webRoot: URL
    var coreBundle: URL
    var database: URL
    var loginUrl: String
    var version: String
    var calendar: Bool = true
    // Test builds only: an access token from elsewhere (the Salesforce CLI) instead of signing in.
    var testToken: (() -> SalesforceAuth.Token?)?
  }

  private let config: Config
  private weak var ui: HostUI?
  let auth: SalesforceAuth
  private var core: CoreRuntime!
  private(set) var web: WKWebView!
  private var stopped = Set<ObjectIdentifier>()
  private var downloads: [ObjectIdentifier: URL] = [:]

  init(config: Config, ui: HostUI) throws {
    self.config = config
    self.ui = ui
    auth = SalesforceAuth(loginUrl: config.loginUrl)
    super.init()
    let refresh: (@escaping (Result<SalesforceAuth.Token, Error>) -> Void) -> Void = { [weak self] done in
      guard let self else { return }
      if let test = self.config.testToken {
        return done(test().map { .success($0) } ?? .failure(SalesforceAuth.AuthError("No test token.")))
      }
      self.auth.refresh(done)
    }
    core = try CoreRuntime(bundle: config.coreBundle, db: SQLiteStore(file: config.database),
                           calendar: config.calendar ? CalendarReader() : nil, version: config.version,
                           refresh: refresh, signOut: { [weak self] in self?.auth.signOut() })

    let wc = WKWebViewConfiguration()
    wc.setURLSchemeHandler(self, forURLScheme: Self.scheme)
    wc.websiteDataStore = .default()
    #if os(iOS)
    wc.allowsInlineMediaPlayback = true
    wc.dataDetectorTypes = []
    #endif
    web = WKWebView(frame: .zero, configuration: wc)
    web.navigationDelegate = self
    web.uiDelegate = self
    #if DEBUG
    if #available(iOS 16.4, macOS 13.3, *) { web.isInspectable = true }
    #endif
  }

  // On launch: with a saved login, renew it and connect before showing the page; otherwise the page shows Connect.
  func start() {
    ui?.show(page: web)
    if let test = config.testToken?() {
      return connect(test) { self.web.load(URLRequest(url: Self.home)) }
    }
    guard let login = auth.login else {
      web.load(URLRequest(url: Self.home))
      return
    }
    auth.refresh { result in
      switch result {
      case .success(let t): self.connect(t) { self.web.load(URLRequest(url: Self.home)) }
      case .failure:
        // Offline: open on the saved copy (the core falls back to the last user it saw), unless the login expired.
        if self.auth.login != nil, self.auth.savedUserJson != nil {
          self.connect((login.instanceUrl, "")) { self.web.load(URLRequest(url: Self.home)) }
        } else {
          self.web.load(URLRequest(url: Self.home))
        }
      }
    }
  }

  private func connect(_ t: SalesforceAuth.Token, then: @escaping () -> Void) {
    core.connect(instanceUrl: t.instanceUrl, accessToken: t.accessToken, savedUserJson: auth.savedUserJson) { reply in
      if let user = reply["user"], reply["offline"] == nil,
         let data = try? JSONSerialization.data(withJSONObject: user), let json = String(data: data, encoding: .utf8) {
        self.auth.saveUser(json)
      }
      if let error = reply["error"] { NSLog("SF Desk: connecting failed: %@", "\(error)") }
      then()
    }
  }

  func signIn() {
    if let test = config.testToken?() {
      return connect(test) { self.web.load(URLRequest(url: Self.home)) }
    }
    let view = auth.signInView { [weak self] result in
      guard let self else { return }
      self.ui?.show(page: self.web)
      switch result {
      case .success(let t): self.connect(t) { self.web.load(URLRequest(url: Self.home)) }
      case .failure(let err): self.ui?.alert(err.localizedDescription) {}
      }
    }
    ui?.show(signIn: view) { [weak self] in
      self?.auth.cancelSignIn()
    }
  }

  // MARK: sfdesk://app/

  func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
    let request = task.request
    guard let url = request.url else { return task.didFailWithError(URLError(.badURL)) }
    if url.path.hasPrefix("/api/") || url.path == "/api" {
      var body: String?
      if let data = request.httpBody {
        body = String(data: data, encoding: .utf8)
      } else if let stream = request.httpBodyStream {
        body = String(data: Self.read(stream), encoding: .utf8)
      }
      let pathAndQuery = String(url.path.dropFirst(4)) + (url.query.map { "?" + $0 } ?? "")
      let headers = request.allHTTPHeaderFields ?? [:]
      let json: [String: Any] = ["method": request.httpMethod ?? "GET", "url": pathAndQuery.isEmpty ? "/" : pathAndQuery,
                                 "headers": headers, "body": body ?? NSNull()]
      let text = String(data: try! JSONSerialization.data(withJSONObject: json), encoding: .utf8)!
      core.handle(text) { [weak self] out in
        guard let self, !self.stopped.contains(ObjectIdentifier(task)) else { return }
        let status = out["status"] as? Int ?? 500
        var headers = (out["headers"] as? [String: Any] ?? [:]).mapValues { "\($0)" }
        if headers.keys.first(where: { $0.lowercased() == "content-type" }) == nil {
          headers["Content-Type"] = "application/json; charset=utf-8"
        }
        headers["Cache-Control"] = "no-store"
        let data = Data((out["body"] as? String ?? "").utf8)
        self.respond(task, url: url, status: status, headers: headers, data: data)
      }
      return
    }

    var path = url.path.isEmpty || url.path == "/" ? "/index.html" : url.path
    if path.hasSuffix("/") { path += "index.html" }
    let file = config.webRoot.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
    guard file.path.hasPrefix(config.webRoot.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
      return respond(task, url: url, status: 404, headers: ["Content-Type": "text/plain"], data: Data("Not found".utf8))
    }
    let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    let text = type.hasPrefix("text/") || type.contains("javascript") || type.contains("json") || type.contains("svg")
    respond(task, url: url, status: 200, headers: ["Content-Type": text ? type + "; charset=utf-8" : type, "Cache-Control": "no-cache"], data: data)
  }

  func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
    stopped.insert(ObjectIdentifier(task))
  }

  private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, headers: [String: String], data: Data) {
    let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    task.didReceive(response)
    if !data.isEmpty { task.didReceive(data) }
    task.didFinish()
    stopped.remove(ObjectIdentifier(task))
  }

  private static func read(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while stream.hasBytesAvailable {
      let n = stream.read(&buffer, maxLength: buffer.count)
      if n <= 0 { break }
      data.append(buffer, count: n)
    }
    return data
  }

  // MARK: navigation

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if action.shouldPerformDownload { return decisionHandler(.download) }
    guard let url = action.request.url else { return decisionHandler(.cancel) }
    if url.scheme == Self.scheme {
      if url.path == "/login" {
        decisionHandler(.cancel)
        return signIn()
      }
      return decisionHandler(.allow)
    }
    if url.scheme == "blob" || url.scheme == "data" || url.scheme == "about" { return decisionHandler(.allow) }
    // Salesforce and other links open in the browser (or the Salesforce app), not in place of the page.
    decisionHandler(.cancel)
    ui?.open(external: url)
  }

  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    decisionHandler(response.canShowMIMEType ? .allow : .download)
  }

  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
    download.delegate = self
  }

  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
    download.delegate = self
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    webView.reload()
  }

  // window.open and target=_blank links.
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
               for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if let url = action.request.url {
      if url.scheme == Self.scheme { webView.load(action.request) } else { ui?.open(external: url) }
    }
    return nil
  }

  // MARK: alert, confirm, prompt

  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
               initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
    guard let ui else { return completionHandler() }
    ui.alert(message, done: completionHandler)
  }

  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
               initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
    guard let ui else { return completionHandler(false) }
    ui.confirm(message, done: completionHandler)
  }

  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
               initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
    guard let ui else { return completionHandler(nil) }
    ui.prompt(prompt, defaultText: defaultText, done: completionHandler)
  }

  // MARK: downloads (Excel exports)

  func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                completionHandler: @escaping (URL?) -> Void) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent(suggestedFilename.isEmpty ? "SF Desk export" : suggestedFilename)
    try? FileManager.default.removeItem(at: file)
    downloads[ObjectIdentifier(download)] = file
    completionHandler(file)
  }

  func downloadDidFinish(_ download: WKDownload) {
    guard let file = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
    ui?.share(file: file)
  }

  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    downloads.removeValue(forKey: ObjectIdentifier(download))
    ui?.alert("The download failed: \(error.localizedDescription)") {}
  }
}
