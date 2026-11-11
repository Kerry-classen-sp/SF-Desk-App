#if os(macOS)
import AppKit
import WebKit

// The iPhone app's host in a phone-sized Mac window, to test it without an iPhone or Xcode
// (ios/build-mac-test.sh). Settings, all optional:
//   SFDESK_TEST_INSTANCE, SFDESK_TEST_TOKEN  an access token (from the Salesforce CLI) instead of signing in
//   SFDESK_SELFTEST=<dir>                    open each tab, call the API, export to Excel, save screenshots
//                                            and results.json in <dir>, then quit
//   SFDESK_STEPS=<file>                      with SFDESK_SELFTEST: instead of the standard test, run the file's
//                                            JavaScript steps (separated by lines of ---), a screenshot after each
//   SFDESK_WIDTH=<points>                    the window's width (default 393, an iPhone's)
//   SFDESK_NO_CALENDAR=1                     no calendar (Time Entry shows Salesforce only)
//   SFDESK_DATA=<dir>                        where the database goes (default: Application Support/SF Desk iOS Test)
final class MacTestApp: NSObject, NSApplicationDelegate, HostUI {
  private var window: NSWindow!
  private var controller: AppController!
  private var signInWindow: NSWindow?
  private let env = ProcessInfo.processInfo.environment
  private var selfTest: URL? { env["SFDESK_SELFTEST"].map { URL(fileURLWithPath: $0, isDirectory: true) } }
  private var dialogs: [String] = []
  private var shared: [URL] = []

  func applicationDidFinishLaunching(_ note: Notification) {
    let width = Double(env["SFDESK_WIDTH"] ?? "") ?? 393
    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 852), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                      backing: .buffered, defer: false)
    window.title = "SF Desk (iPhone)"
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    let res = Bundle.main.resourceURL!
    let data = env["SFDESK_DATA"].map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SF Desk iOS Test")
    var config = AppController.Config(
      webRoot: res.appendingPathComponent("web"), coreBundle: res.appendingPathComponent("core-bundle.js"),
      database: data.appendingPathComponent("sf-desk.db"),
      loginUrl: Bundle.main.object(forInfoDictionaryKey: "SFDeskLoginURL") as? String ?? "https://login.salesforce.com",
      version: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") + " (iPhone test)")
    config.calendar = env["SFDESK_NO_CALENDAR"] == nil
    if let instance = env["SFDESK_TEST_INSTANCE"], let token = env["SFDESK_TEST_TOKEN"] {
      config.testToken = { (instance, token) }
    }
    do {
      controller = try AppController(config: config, ui: self)
    } catch {
      fail("Couldn't start: \(error.localizedDescription)")
      return
    }
    if selfTest != nil {
      controller.web.configuration.userContentController.addUserScript(WKUserScript(source: """
        window.__errors = [];
        addEventListener('error', (e) => __errors.push('error: ' + e.message + ' @' + e.filename + ':' + e.lineno));
        addEventListener('unhandledrejection', (e) => __errors.push('rejection: ' + (e.reason?.stack || e.reason)));
        const ce = console.error.bind(console);
        console.error = (...a) => { __errors.push('console: ' + a.map(String).join(' ')); ce(...a); };
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }
    controller.start()
    if let dir = selfTest { Task { @MainActor in await self.runSelfTest(dir) } }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

  private func fail(_ text: String) {
    NSLog("SF Desk test: %@", text)
    if let dir = selfTest {
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try? Data(#"{"error":\#(Self.quote(text))}"#.utf8).write(to: dir.appendingPathComponent("results.json"))
      exit(1)
    }
  }

  private static func quote(_ s: String) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed), encoding: .utf8)!
  }

  // MARK: HostUI

  func show(page: WKWebView) {
    signInWindow?.close()
    signInWindow = nil
    if window.contentView !== page { window.contentView = page }
  }

  func show(signIn: WKWebView, cancel: @escaping () -> Void) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 720), styleMask: [.titled, .closable, .resizable],
                     backing: .buffered, defer: false)
    w.title = "Sign in to Salesforce"
    w.contentView = signIn
    w.isReleasedWhenClosed = false
    w.center()
    w.makeKeyAndOrderFront(nil)
    signInWindow = w
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
      if self?.signInWindow === w { self?.signInWindow = nil; cancel() }
    }
  }

  private func panel(_ message: String, buttons: [String]) -> NSAlert {
    let a = NSAlert()
    a.messageText = message
    buttons.forEach { a.addButton(withTitle: $0) }
    return a
  }

  func confirm(_ message: String, done: @escaping (Bool) -> Void) {
    if selfTest != nil { dialogs.append("confirm: " + message); return done(false) }
    panel(message, buttons: ["OK", "Cancel"]).beginSheetModal(for: window) { done($0 == .alertFirstButtonReturn) }
  }

  func alert(_ message: String, done: @escaping () -> Void) {
    if selfTest != nil { dialogs.append("alert: " + message); return done() }
    panel(message, buttons: ["OK"]).beginSheetModal(for: window) { _ in done() }
  }

  func prompt(_ message: String, defaultText: String?, done: @escaping (String?) -> Void) {
    if selfTest != nil { dialogs.append("prompt: " + message); return done(nil) }
    let a = panel(message, buttons: ["OK", "Cancel"])
    let field = NSTextField(string: defaultText ?? "")
    field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
    a.accessoryView = field
    a.beginSheetModal(for: window) { done($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
  }

  func share(file: URL) {
    shared.append(file)
    if selfTest == nil { NSWorkspace.shared.activateFileViewerSelecting([file]) }
  }

  func open(external url: URL) {
    if selfTest != nil { dialogs.append("open: " + url.absoluteString); return }
    NSWorkspace.shared.open(url)
  }

  // MARK: self-test

  @MainActor private func js(_ code: String) async -> Any? {
    do { return try await controller.web.callAsyncJavaScript(code, contentWorld: .page) }
    catch { return "JS error: \(error)" }
  }

  @MainActor private func snapshot(_ name: String, _ dir: URL) async {
    guard let image = try? await controller.web.takeSnapshot(configuration: nil),
          let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: dir.appendingPathComponent(name + ".png"))
  }

  @MainActor private func waitFor(_ condition: String, seconds: Double) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
      if await js("return !!(\(condition))") as? Bool == true { return true }
      try? await Task.sleep(nanoseconds: 500_000_000)
    }
    return false
  }

  @MainActor private func runSelfTest(_ dir: URL) async {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var results: [String: Any] = [:]
    let busy = "document.querySelector('#app .spin, #app .loading')"
    let loaded = await waitFor("document.getElementById('who')?.textContent || document.querySelector('#app .card h2')", seconds: 90)
    results["pageLoaded"] = loaded
    results["who"] = await js("return document.getElementById('who').textContent")
    let deals0 = Date()
    _ = await waitFor("!(\(busy))", seconds: 120)
    if let file = env["SFDESK_STEPS"], let script = try? String(contentsOfFile: file, encoding: .utf8) {
      var steps: [Any] = []
      for (i, step) in script.components(separatedBy: "\n---\n").enumerated() {
        steps.append(await js(step) ?? NSNull())
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await snapshot("step-\(i + 1)", dir)
      }
      results["steps"] = steps
      results["pageErrors"] = await js("return window.__errors")
      let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
      try? data.write(to: dir.appendingPathComponent("results.json"))
      NSApp.terminate(nil)
      return
    }
    results["dealsMs"] = Int(Date().timeIntervalSince(deals0) * 1000)
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    await snapshot("1-deals", dir)

    var tabs: [String: Any] = [:]
    let loading = "[...document.querySelectorAll('#app *')].some((e) => !e.children.length && /^Loading/.test(e.textContent.trim()))"
    for (i, id) in ["navAccts", "navTime", "navTeam", "navCal", "navTes"].enumerated() {
      let t0 = Date()
      _ = await js("document.getElementById('\(id)').click()")
      try? await Task.sleep(nanoseconds: 300_000_000)
      let done = await waitFor("!(\(loading))", seconds: 120)
      let ms = Int(Date().timeIntervalSince(t0) * 1000)
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      let text = await js("return (document.querySelector('#app h2')?.textContent || '') + ' | ' + document.getElementById('app').innerText.length + ' chars'")
      tabs[id] = "\(done ? "loaded" : "STILL LOADING") in \(ms) ms: \(text ?? "")"
      await snapshot("\(i + 2)-\(id)", dir)
    }
    results["tabs"] = tabs

    results["api"] = await js("""
      const out = {};
      for (const p of ['/api/me', '/api/meta', '/api/hidden', '/api/prefs/accounts', '/api/deal-supports/meta',
                       '/api/pipeline?boat=all&team=mine&status=won', '/api/opportunities/open?q=sinai&limit=50',
                       '/api/calendar/sources', '/api/my-time', '/api/no-such-route']) {
        const t0 = Date.now();
        const r = await fetch(p);
        const text = await r.text();
        out[p] = r.status + ' ' + text.length + ' bytes ' + (Date.now() - t0) + ' ms' + (r.ok ? '' : ' ' + text.slice(0, 200));
      }
      const noHeader = await fetch('/api/prefs/accounts', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: '{}' });
      out.putWithoutHeader = noHeader.status + ' ' + (await noHeader.text());
      const before = await (await fetch('/api/prefs/accounts')).json();
      const put = await fetch('/api/prefs/accounts', { method: 'PUT', headers: { 'Content-Type': 'application/json', 'X-SFDesk': '1' },
        body: JSON.stringify({ ...before, repName: 'self-test ' + Date.now() }) });
      const saved = await put.json();
      const after = await (await fetch('/api/prefs/accounts')).json();
      out.putBody = put.status + ' ' + (after.repName === saved.repName && /^self-test/.test(after.repName) ? 'saved and read back' : 'NOT SAVED ' + JSON.stringify(after));
      await fetch('/api/prefs/accounts', { method: 'PUT', headers: { 'Content-Type': 'application/json', 'X-SFDesk': '1' }, body: JSON.stringify(before) });
      return out;
      """)

    shared = []
    _ = await js("await downloadXlsx('Self test.xlsx', 'Test', [{ header: 'Name' }, { header: 'Amount', type: 'money' }], [['A', 1], ['B', 2.5]])")
    _ = await waitFor("false", seconds: 3)
    results["excel"] = shared.map { url -> String in
      let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
      let head = (try? Data(contentsOf: url).prefix(2)).map { String(decoding: $0, as: UTF8.self) } ?? ""
      return "\(url.lastPathComponent) \(size) bytes \(head == "PK" ? "zip ok" : "NOT A ZIP")"
    }
    _ = await js("confirm('Self-test confirm?')")
    _ = await js("document.body.append(Object.assign(document.createElement('a'), { id: 'ext', href: 'https://sailpoint.my.salesforce.com/', target: '_blank' })); document.getElementById('ext').click()")
    try? await Task.sleep(nanoseconds: 500_000_000)
    results["dialogs"] = dialogs
    results["timeProbe"] = await js("""
      showTime();
      const t0 = Date.now();
      while (Date.now() - t0 < 90000 && document.getElementById('timeSub')?.textContent === 'Loading…') await new Promise((r) => setTimeout(r, 250));
      return (Date.now() - t0) + ' ms: ' + document.getElementById('app').innerText.slice(0, 300);
      """)
    results["pageErrors"] = await js("return window.__errors")

    let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
    try? data.write(to: dir.appendingPathComponent("results.json"))
    NSApp.terminate(nil)
  }
}

@main
enum Main {
  static func main() {
    let app = NSApplication.shared
    let delegate = MacTestApp()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
  }
}
#endif
