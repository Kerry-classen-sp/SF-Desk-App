# SF Desk: possible future upgrades

Ideas kept for later. Nothing here is built yet.

## iOS app

Built in `ios/` (see [docs/IOS.md](IOS.md)): the shared core in JavaScriptCore, the page in a web
view, and the Salesforce CLI's connected app for sign-in. Still to do:

- **Distribution:** TestFlight is set up (`ios/testflight.sh`, see [docs/IOS.md](IOS.md#testflight)) on Kerry's
  Apple Developer team; move it to the company's Apple Developer account, or company device management, for wider use.
- **Own connected app:** if Salesforce or IT ever limits the CLI's `PlatformCLI` app, an SF Desk connected
  app (or External Client App) with a `sfdesk://` callback, opened in `ASWebAuthenticationSession`.
- **Touch wording:** Calendar says "right-click it to create…". On a phone, say "tap it", and offer the
  quick menu on a long press.

## Smaller ideas offered along the way

- Excel exports follow the sort clicked in the table.
- Deals: include overdue deals in the forecast period's Closing table.
- Leave "Renewal with Upsell" out of Deals and My Team too.
- My Team: leave Deal Support time on renewal opportunities out of the time rankings.
