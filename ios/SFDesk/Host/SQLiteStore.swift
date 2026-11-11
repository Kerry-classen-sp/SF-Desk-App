import Foundation
import SQLite3

// The app's SQLite file, for the shared core's store (src/store.js) through host.js's nativeDb: one call per
// statement, parameters and results as JSON. Positional parameters come as an array, named ones (@name)
// as an object. Used only on CoreRuntime's queue.
final class SQLiteStore {
  private var db: OpaquePointer?
  private var statements: [String: OpaquePointer] = [:]
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(file: URL) throws {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      throw NSError(domain: "SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Can't open \(file.path)"])
    }
  }

  deinit {
    statements.values.forEach { sqlite3_finalize($0) }
    sqlite3_close(db)
  }

  // op: exec | all | get | run. Returns {"result": ...} or {"error": "..."}.
  func call(op: String, sql: String, paramsJson: String) -> String {
    do {
      let result: Any = op == "exec" ? try exec(sql) : try run(op, sql, JSONSerialization.jsonObject(with: Data(paramsJson.utf8)))
      return Self.json(["result": result])
    } catch {
      return Self.json(["error": (error as NSError).localizedDescription])
    }
  }

  private var message: String { String(cString: sqlite3_errmsg(db)) }
  private func fail() -> NSError { NSError(domain: "SQLite", code: Int(sqlite3_errcode(db)), userInfo: [NSLocalizedDescriptionKey: message]) }

  private func exec(_ sql: String) throws -> Any {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw fail() }
    return NSNull()
  }

  private func run(_ op: String, _ sql: String, _ params: Any) throws -> Any {
    let stmt: OpaquePointer
    if let cached = statements[sql] {
      stmt = cached
    } else {
      var made: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &made, nil) == SQLITE_OK, let made else { throw fail() }
      statements[sql] = made
      stmt = made
    }
    defer { sqlite3_reset(stmt); sqlite3_clear_bindings(stmt) }

    let count = sqlite3_bind_parameter_count(stmt)
    if count > 0 {
      for i in 1...count {
        let value: Any?
        if let list = params as? [Any] {
          value = Int(i) <= list.count ? list[Int(i) - 1] : nil
        } else if let named = params as? [String: Any], let cName = sqlite3_bind_parameter_name(stmt, i) {
          value = named[String(String(cString: cName).dropFirst())]
        } else {
          value = nil
        }
        try bind(stmt, i, value)
      }
    }

    var rows: [[String: Any]] = []
    while true {
      let rc = sqlite3_step(stmt)
      if rc == SQLITE_DONE { break }
      guard rc == SQLITE_ROW else { throw fail() }
      if op == "run" { continue }
      var row: [String: Any] = [:]
      for c in 0..<sqlite3_column_count(stmt) {
        let name = String(cString: sqlite3_column_name(stmt, c))
        switch sqlite3_column_type(stmt, c) {
        case SQLITE_INTEGER: row[name] = sqlite3_column_int64(stmt, c)
        case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt, c)
        case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(stmt, c))
        default: row[name] = NSNull()
        }
      }
      rows.append(row)
      if op == "get" { break }
    }
    switch op {
    case "all": return rows
    case "get": return rows.first ?? NSNull()
    default: return ["changes": Int(sqlite3_changes(db))]
    }
  }

  private func bind(_ stmt: OpaquePointer, _ i: Int32, _ value: Any?) throws {
    let rc: Int32
    switch value {
    case nil, is NSNull: rc = sqlite3_bind_null(stmt, i)
    case let n as NSNumber:
      if CFGetTypeID(n) == CFBooleanGetTypeID() { rc = sqlite3_bind_int64(stmt, i, n.boolValue ? 1 : 0) }
      else if CFNumberIsFloatType(n), n.doubleValue != n.doubleValue.rounded() { rc = sqlite3_bind_double(stmt, i, n.doubleValue) }
      else { rc = sqlite3_bind_int64(stmt, i, n.int64Value) }
    case let s as String: rc = sqlite3_bind_text(stmt, i, s, -1, Self.transient)
    default:
      let data = try JSONSerialization.data(withJSONObject: value!)
      rc = sqlite3_bind_text(stmt, i, String(data: data, encoding: .utf8), -1, Self.transient)
    }
    guard rc == SQLITE_OK else { throw fail() }
  }

  private static func json(_ value: Any) -> String {
    (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])).flatMap { String(data: $0, encoding: .utf8) }
      ?? #"{"error":"Couldn't encode the SQLite result"}"#
  }
}
