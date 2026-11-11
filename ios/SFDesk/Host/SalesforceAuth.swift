import CryptoKit
import Foundation
import WebKit

// Signing in to Salesforce without a connected app of our own: the Salesforce CLI's (PlatformCLI, which
// every org has) with PKCE. Its login page (My Domain, then SSO) shows in a web view; the redirect to
// http://localhost:1717/OauthRedirect is caught there, never loaded. The refresh token is kept in the
// Keychain; access tokens only in memory.
final class SalesforceAuth: NSObject, WKNavigationDelegate, WKUIDelegate {
  struct Login: Codable {
    var loginUrl: String
    var instanceUrl: String
    var refreshToken: String
  }
  typealias Token = (instanceUrl: String, accessToken: String)
  struct AuthError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }

  static let clientId = "PlatformCLI"
  static let redirect = "http://localhost:1717/OauthRedirect"
  private static let loginKey = "login", userKey = "user"

  let loginUrl: String
  private(set) var login: Login?
  private var refreshing: [(Result<Token, Error>) -> Void] = []

  // Sign-in in progress.
  private var verifier = "", state = ""
  private var finishSignIn: ((Result<Token, Error>) -> Void)?

  init(loginUrl: String) {
    self.loginUrl = loginUrl.hasSuffix("/") ? String(loginUrl.dropLast()) : loginUrl
    if let data = Keychain.load(Self.loginKey) { login = try? JSONDecoder().decode(Login.self, from: data) }
    super.init()
  }

  var savedUserJson: String? { Keychain.load(Self.userKey).flatMap { String(data: $0, encoding: .utf8) } }
  func saveUser(_ json: String) { Keychain.save(Data(json.utf8), for: Self.userKey) }

  // A web view showing Salesforce's login page; `done` gets the new access token, or an error.
  func signInView(done: @escaping (Result<Token, Error>) -> Void) -> WKWebView {
    var random = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
    verifier = Self.base64url(Data(random))
    state = UUID().uuidString
    finishSignIn = done

    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    let web = WKWebView(frame: .zero, configuration: config)
    web.navigationDelegate = self
    web.uiDelegate = self
    var url = URLComponents(string: loginUrl + "/services/oauth2/authorize")!
    url.queryItems = [
      .init(name: "response_type", value: "code"), .init(name: "client_id", value: Self.clientId),
      .init(name: "redirect_uri", value: Self.redirect), .init(name: "scope", value: "refresh_token api web"),
      .init(name: "code_challenge", value: Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))),
      .init(name: "code_challenge_method", value: "S256"), .init(name: "state", value: state),
    ]
    web.load(URLRequest(url: url.url!))
    return web
  }

  func cancelSignIn() {
    finishSignIn = nil
  }

  // Sign-in pages that open a new window load in this one.
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
               for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if let url = action.request.url { webView.load(URLRequest(url: url)) }
    return nil
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if let url = action.request.url, caught(url) { return decisionHandler(.cancel) }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if let url = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL { _ = caught(url) }
  }

  private func caught(_ url: URL) -> Bool {
    guard url.absoluteString.hasPrefix(Self.redirect), let done = finishSignIn else { return false }
    finishSignIn = nil
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let value = { (name: String) in items.first { $0.name == name }?.value }
    if let error = value("error") {
      done(.failure(AuthError("Salesforce sign-in failed: \(value("error_description") ?? error)")))
    } else if value("state") != state || value("code") == nil {
      done(.failure(AuthError("Salesforce sign-in came back without a code. Try again.")))
    } else {
      token([("grant_type", "authorization_code"), ("code", value("code")!), ("client_id", Self.clientId),
             ("redirect_uri", Self.redirect), ("code_verifier", verifier)]) { result in
        done(result.flatMap { t in
          guard let refresh = t["refresh_token"] as? String, let instance = t["instance_url"] as? String,
                let access = t["access_token"] as? String else { return .failure(AuthError("Salesforce didn't return a login.")) }
          self.login = Login(loginUrl: self.loginUrl, instanceUrl: instance, refreshToken: refresh)
          if let data = try? JSONEncoder().encode(self.login) { Keychain.save(data, for: Self.loginKey) }
          return .success((instance, access))
        })
      }
    }
    return true
  }

  // A new access token from the saved refresh token. Calls made while one is on its way share it.
  func refresh(_ done: @escaping (Result<Token, Error>) -> Void) {
    guard let login else { return done(.failure(AuthError("Not signed in to Salesforce."))) }
    refreshing.append(done)
    guard refreshing.count == 1 else { return }
    token([("grant_type", "refresh_token"), ("client_id", Self.clientId), ("refresh_token", login.refreshToken)], base: login.loginUrl) { result in
      let out: Result<Token, Error> = result.flatMap { t in
        guard let access = t["access_token"] as? String else { return .failure(AuthError("Your Salesforce login expired. Sign in again.")) }
        return .success(((t["instance_url"] as? String) ?? login.instanceUrl, access))
      }
      if case .failure(let err as AuthError) = out, err.errorDescription?.contains("expired") == true { self.forget() }
      let waiting = self.refreshing
      self.refreshing = []
      waiting.forEach { $0(out) }
    }
  }

  func signOut() {
    if let token = login?.refreshToken {
      var req = URLRequest(url: URL(string: (login?.loginUrl ?? loginUrl) + "/services/oauth2/revoke")!)
      req.httpMethod = "POST"
      req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      req.httpBody = Self.form([("token", token)])
      URLSession.shared.dataTask(with: req).resume()
    }
    forget()
  }

  private func forget() {
    login = nil
    Keychain.delete(Self.loginKey)
  }

  private func token(_ pairs: [(String, String)], base: String? = nil, done: @escaping (Result<[String: Any], Error>) -> Void) {
    var req = URLRequest(url: URL(string: (base ?? loginUrl) + "/services/oauth2/token")!)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    req.httpBody = Self.form(pairs)
    URLSession.shared.dataTask(with: req) { data, resp, error in
      let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
      let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
      DispatchQueue.main.async {
        if let error { return done(.failure(AuthError("Can't reach Salesforce (\(error.localizedDescription)).")))}
        if status == 200 { return done(.success(json)) }
        let why = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "HTTP \(status)"
        done(.failure(AuthError(status == 400 ? "Your Salesforce login expired. Sign in again. (\(why))" : "Salesforce sign-in failed: \(why)")))
      }
    }.resume()
  }

  static func form(_ pairs: [(String, String)]) -> Data {
    let ok = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
    return Data(pairs.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: ok)!)" }.joined(separator: "&").utf8)
  }

  static func base64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
