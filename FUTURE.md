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

Built in `ios/` (see [ios/README.md](ios/README.md)): the shared core in JavaScriptCore, the page in a web
view, and the Salesforce CLI's connected app for sign-in. Still to do:

- **Distribution:** TestFlight or company device management, through the company's Apple Developer account.
- **Own connected app:** if Salesforce or IT ever limits the CLI's `PlatformCLI` app, an SF Desk connected
  app (or External Client App) with a `sfdesk://` callback, opened in `ASWebAuthenticationSession`.
- **Touch wording:** Time Entry says "right-click it to create…". On a phone, say "tap it", and offer the
  quick menu on a long press.
- **Microsoft 365 calendar through Graph** once IT approves it, for phones without the Exchange account
  added.

## Smaller ideas offered along the way

- Excel exports follow the sort clicked in the table.
- Deals: include overdue deals in the forecast period's Closing table.
- Leave "Renewal with Upsell" out of Deals and My Team too.
- My Team: leave Deal Support time on renewal opportunities out of the time rankings.
