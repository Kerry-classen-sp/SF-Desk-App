import EventKit
import Foundation

// The device's calendars for Time Entry, through EventKit, as the Mac's helper (mac/calendar.swift) reads
// them: the accounts added in Settings > Calendar > Accounts (Exchange, iCloud, Google...). Answers are
// JSON for host.js; {"error": "denied", ...} when calendar access isn't allowed.
final class CalendarReader {
  private let store = EKEventStore()
  private var allowed: Bool?
  private let iso = ISO8601DateFormatter()
  private let day: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
  }()

  private func access(_ then: @escaping (Bool) -> Void) {
    if let allowed { return then(allowed) }
    let done: (Bool, Error?) -> Void = { ok, _ in self.allowed = ok; then(ok) }
    if #available(iOS 17.0, macOS 14.0, *) { store.requestFullAccessToEvents(completion: done) }
    else { store.requestAccess(to: .event, completion: done) }
  }

  private static let denied = ["error": "denied", "message":
    "SF Desk isn't allowed to read your calendars. In Settings > Privacy & Security > Calendars, give SF Desk full access, then reload."]

  private func sourceType(_ t: EKSourceType) -> String {
    switch t {
    case .local: return "local"
    case .exchange: return "exchange"
    case .calDAV: return "caldav"
    case .mobileMe: return "icloud"
    case .subscribed: return "subscribed"
    case .birthdays: return "birthdays"
    @unknown default: return "other"
    }
  }

  func calendars(_ done: @escaping (Any) -> Void) {
    access { ok in
      guard ok else { return done(Self.denied) }
      done(self.store.calendars(for: .event).map { c in [
        "id": c.calendarIdentifier, "title": c.title, "account": c.source.title,
        "type": self.sourceType(c.source.sourceType), "writable": c.allowsContentModifications,
      ] as [String: Any] })
    }
  }

  func events(from: String, to: String, ids: [String], _ done: @escaping (Any) -> Void) {
    access { ok in
      guard ok else { return done(Self.denied) }
      guard let start = self.iso.date(from: from), let end = self.iso.date(from: to) else {
        return done(["error": "usage", "message": "Invalid time range"])
      }
      let wanted = Set(ids)
      let calendars = self.store.calendars(for: .event).filter { wanted.contains($0.calendarIdentifier) }
      if calendars.isEmpty { return done([Any]()) }
      let events = self.store.events(matching: self.store.predicateForEvents(withStart: start, end: end, calendars: calendars))
      done(events.map { e -> [String: Any] in
        let attendees: [[String: Any]] = (e.attendees ?? []).map { p in
          let email = p.url.absoluteString.hasPrefix("mailto:") ? String(p.url.absoluteString.dropFirst(7)) : ""
          return ["name": p.name ?? "", "email": email.removingPercentEncoding ?? email, "me": p.isCurrentUser]
        }
        return [
          // Occurrences of a repeating event share an identifier; host.js adds the start to tell them apart.
          "uid": e.calendarItemExternalIdentifier ?? e.eventIdentifier ?? "",
          "title": e.title ?? "",
          "start": self.iso.string(from: e.startDate),
          "end": self.iso.string(from: e.endDate),
          "date": self.day.string(from: e.startDate),
          "allDay": e.isAllDay,
          "location": e.location ?? "",
          "notes": e.notes ?? "",
          "calendar": e.calendar.title,
          "calendarId": e.calendar.calendarIdentifier,
          "organizer": e.organizer?.name ?? "",
          "attendees": attendees,
          "canceled": e.status == .canceled,
          "free": e.availability == .free,
        ]
      })
    }
  }
}
