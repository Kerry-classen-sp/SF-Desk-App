import Foundation
import JavaScriptCore

// Runs the shared core (Generated/core-bundle.js: src/ plus Host/host.js) in JavaScriptCore, on one queue,
// and gives it the `native` functions host.js describes. The page's API calls come in through handle().
final class CoreRuntime {
  private let queue = DispatchQueue(label: "SF Desk core")
  private var context: JSContext!
  private let db: SQLiteStore
  private let refresher: (@escaping (Result<SalesforceAuth.Token, Error>) -> Void) -> Void
  private let signOutHandler: () -> Void
  private let calendar: CalendarReader?
  private let session = URLSession(configuration: .ephemeral)

  init(bundle: URL, db: SQLiteStore, calendar: CalendarReader?, version: String,
       refresh: @escaping (@escaping (Result<SalesforceAuth.Token, Error>) -> Void) -> Void, signOut: @escaping () -> Void) throws {
    self.db = db
    self.refresher = refresh
    self.signOutHandler = signOut
    self.calendar = calendar
    let source = try String(contentsOf: bundle, encoding: .utf8)
    var failure: String?
    queue.sync {
      context = JSContext()
      context.name = "SF Desk core"
      context.exceptionHandler = { _, exception in
        let text = "\(exception?.toString() ?? "?") \(exception?.objectForKeyedSubscript("stack")?.toString() ?? "")"
        NSLog("SF Desk core: uncaught %@", text)
        failure = failure ?? text
      }
      context.setObject(makeNative(version: version), forKeyedSubscript: "native" as NSString)
      context.evaluateScript(source, withSourceURL: URL(string: "core-bundle.js"))
    }
    if let failure { throw NSError(domain: "SF Desk core", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
  }

  // Calls back on CoreRuntime's queue, with a JSON string.
  private func reply(_ callback: JSValue, _ value: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data("null".utf8)
    let text = String(data: data, encoding: .utf8) ?? "null"
    queue.async { callback.call(withArguments: [text]) }
  }

  private func makeNative(version: String) -> JSValue {
    let native = JSValue(newObjectIn: context)!
    native.setObject(version, forKeyedSubscript: "version" as NSString)
    native.setObject(calendar != nil, forKeyedSubscript: "hasCalendar" as NSString)

    let log: @convention(block) (String, String) -> Void = { level, text in
      #if !DEBUG
      // Release builds (TestFlight) keep warnings and errors only: other messages can name records.
      guard level == "warn" || level == "error" else { return }
      #endif
      NSLog("SF Desk core [%@] %@", level, text)
    }
    native.setObject(log, forKeyedSubscript: "log" as NSString)

    let sql: @convention(block) (String, String, String) -> String = { [db] op, text, params in
      db.call(op: op, sql: text, paramsJson: params)
    }
    native.setObject(sql, forKeyedSubscript: "sql" as NSString)

    let fetch: @convention(block) (String, JSValue) -> Void = { [weak self] requestJson, callback in
      guard let self else { return }
      guard let r = (try? JSONSerialization.jsonObject(with: Data(requestJson.utf8))) as? [String: Any],
            let url = URL(string: r["url"] as? String ?? "") else { return self.reply(callback, ["error": "Bad request"]) }
      var req = URLRequest(url: url, timeoutInterval: 120)
      req.httpMethod = r["method"] as? String ?? "GET"
      for (k, v) in r["headers"] as? [String: String] ?? [:] { req.setValue(v, forHTTPHeaderField: k) }
      if let body = r["body"] as? String { req.httpBody = Data(body.utf8) }
      #if DEBUG
      let started = Date()
      #endif
      self.session.dataTask(with: req) { data, resp, error in
        #if DEBUG
        NSLog("SF Desk fetch %d ms %d %@ %@", Int(Date().timeIntervalSince(started) * 1000), (resp as? HTTPURLResponse)?.statusCode ?? 0,
              "\(data?.count ?? 0) bytes", String(url.absoluteString.prefix(160)))
        #endif
        if let error { return self.reply(callback, ["error": error.localizedDescription]) }
        let http = resp as! HTTPURLResponse
        var headers: [String: String] = [:]
        for (k, v) in http.allHeaderFields { headers["\(k)"] = "\(v)" }
        self.reply(callback, ["status": http.statusCode, "statusText": HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                              "headers": headers, "body": String(data: data ?? Data(), encoding: .utf8) ?? ""])
      }.resume()
    }
    native.setObject(fetch, forKeyedSubscript: "fetch" as NSString)

    let refresh: @convention(block) (JSValue) -> Void = { [weak self] callback in
      DispatchQueue.main.async {
        self?.refresher { result in
          switch result {
          case .success(let t): self?.reply(callback, ["accessToken": t.accessToken, "instanceUrl": t.instanceUrl])
          case .failure(let err): self?.reply(callback, ["error": err.localizedDescription])
          }
        }
      }
    }
    native.setObject(refresh, forKeyedSubscript: "refresh" as NSString)

    let signOut: @convention(block) () -> Void = { [weak self] in DispatchQueue.main.async { self?.signOutHandler() } }
    native.setObject(signOut, forKeyedSubscript: "signOut" as NSString)

    let calendars: @convention(block) (JSValue) -> Void = { [weak self] callback in
      DispatchQueue.main.async { self?.calendar?.calendars { self?.reply(callback, $0) } }
    }
    native.setObject(calendars, forKeyedSubscript: "calendars" as NSString)

    let events: @convention(block) (String, String, String, JSValue) -> Void = { [weak self] from, to, idsJson, callback in
      let ids = (try? JSONSerialization.jsonObject(with: Data(idsJson.utf8))) as? [String] ?? []
      DispatchQueue.main.async { self?.calendar?.events(from: from, to: to, ids: ids) { self?.reply(callback, $0) } }
    }
    native.setObject(events, forKeyedSubscript: "events" as NSString)
    return native
  }

  // Calls a host.js function whose last argument is a reply callback; `done` gets the reply on the main queue.
  private func callHost(_ name: String, _ args: [Any], done: @escaping (String) -> Void) {
    queue.async {
      let callback: @convention(block) (String) -> Void = { text in DispatchQueue.main.async { done(text) } }
      self.context.objectForKeyedSubscript(name).call(withArguments: args + [JSValue(object: callback, in: self.context)!])
    }
  }

  // One API request from the page ({ method, url, headers, body } as JSON); replies { status, headers, body }.
  func handle(_ requestJson: String, done: @escaping ([String: Any]) -> Void) {
    callHost("sfdeskHandle", [requestJson]) { text in
      done((try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        ?? ["status": 500, "headers": [String: String](), "body": #"{"error":"Bad reply from the core"}"#])
    }
  }

  // After signing in, or on launch with a saved login. Replies { user } (maybe offline: true) or { error }.
  func connect(instanceUrl: String, accessToken: String, savedUserJson: String?, done: @escaping ([String: Any]) -> Void) {
    callHost("sfdeskConnect", [instanceUrl, accessToken, savedUserJson ?? NSNull()]) { text in
      done((try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? ["error": "Bad reply from the core"])
    }
  }

  func disconnect() {
    queue.async { self.context.objectForKeyedSubscript("sfdeskDisconnect").call(withArguments: []) }
  }
}
