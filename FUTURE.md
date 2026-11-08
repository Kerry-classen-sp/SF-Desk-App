# SF Desk: possible future upgrades

Ideas kept for later. Nothing here is built yet.

## Once IT approves Microsoft Graph (Calendars.ReadWrite)

See the request for IT in [MS-GRAPH-IT-REQUEST.md](MS-GRAPH-IT-REQUEST.md): delegated `User.Read`, `Calendars.ReadWrite` and `offline_access`, either for
Microsoft's "Microsoft Graph Command Line Tools" client or for an SF Desk app registration of our own.

- **Turn on Mark in Outlook:** build in `SF_DESK_OUTLOOK_MARK=1`, plus the client and tenant IDs
  (`SF_DESK_GRAPH_CLIENT_ID`, `SF_DESK_GRAPH_TENANT`) if IT registers an app, so nobody sets them by hand.
- **Same categories as the add-in:** Graph marking (`markCategory` in `src/graphCalendar.js`) only adds the
  green "Deal Support" category today. Make it add the gray "No DS Required" category to meetings marked as
  needing none, and remove either category from meetings that no longer qualify.
- **Recurring meetings:** Graph can categorize a single occurrence (the add-in can only do the whole series),
  so recurring meetings can get their green or gray category too.
- **Whole week at once:** mark every meeting in the week shown on Time Entry, without opening each one in
  Outlook.

## iOS app

A native iPhone app, without the Outlook add-in (so no HTTPS listener, certificates or manifest).

- **Salesforce sign-in:** the Connected App flow SF Desk already supports (OAuth authorization code with
  PKCE, no client secret), opened in `ASWebAuthenticationSession`, returning to a custom scheme such as
  `sfdesk://oauth/callback`, with tokens kept in the Keychain. Salesforce's Mobile SDK for iOS can do this
  instead. The Salesforce CLI login doesn't work on iOS.
- **Salesforce admin setup:** a Connected App (or External Client App) for SF Desk iOS: that callback URL,
  scopes `api` and `refresh_token, offline_access`, PKCE required, refresh-token policy and permitted users.
  Its Consumer Key is built into the app.
- **What moves into the app:** everything `src/server.js` does besides Outlook: the Salesforce queries and
  saves, the Deal Support form's field and layout logic, matching meetings to Deal Supports (one per
  meeting), and the local SQLite store (offline copies, hidden records, event marks). Either rewritten in
  Swift, or the existing JavaScript run in JavaScriptCore with Swift doing networking, storage and calendar.
- **Calendar:** EventKit (as the Mac's calendar reader does) for the phone's calendars, or Microsoft 365
  through Graph once approved.
- **UI:** the existing page in a `WKWebView` (it already adapts to phones, with the single-day Time Entry
  view), or native SwiftUI screens.
- **Distribution:** an Apple Developer account, then TestFlight, the App Store or company device management.

## Smaller ideas offered along the way

- Excel exports follow the sort clicked in the table.
- Deals: include overdue deals in the forecast period's Closing table.
- Leave "Renewal with Upsell" out of Deals and My Team too.
- My Team: leave Deal Support time on renewal opportunities out of the time rankings.
