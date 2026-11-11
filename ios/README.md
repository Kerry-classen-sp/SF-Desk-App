# SF Desk for iPhone and iPad

The same app as the Mac's, without the Outlook add-in. Nothing in Salesforce needs setting up for it.

## How it works

- **Shared core:** the desktop server's API (`src/core.js`, `src/router.js`, `src/store.js`, `src/sha1.js`)
  runs in JavaScriptCore. `build-core.sh` bundles it with `SFDesk/Host/host.js` into
  `SFDesk/Generated/core-bundle.js`. A change to the API is made once, in `src/`, for both apps.
- **Page:** `public/` (copied to `SFDesk/Generated/web`), unchanged, in a web view at `sfdesk://app/`.
  `WebHost.swift` serves its files and answers its `/api/...` calls through the core, as the desktop server
  does.
- **Native parts (Swift, `SFDesk/Host`):**

  | File | What it does |
  | --- | --- |
  | `SalesforceAuth.swift` | Sign-in and token refresh |
  | `Keychain.swift` | Keeps the saved login |
  | `SQLiteStore.swift` | The local database (offline copies, hidden records, event marks, filters) |
  | `CoreRuntime.swift` | Salesforce calls through URLSession, which a page can't make itself |
  | `CalendarReader.swift` | The phone's calendars, through EventKit |

- **Salesforce sign-in:** uses the Salesforce CLI's connected app (`PlatformCLI`, which every org has), with
  PKCE. The org's login page (`SFDeskLoginURL` in `SFDesk/Info.plist`, the My Domain) opens in the app and
  continues to SSO. The refresh token stays in the Keychain. **Disconnect** revokes it.
- **Calendar:** Time Entry reads the calendars added under Settings > Calendar > Accounts on the device,
  such as Exchange or iCloud.

## Build for an iPhone

You need Xcode, with its license accepted (`sudo xcodebuild -license accept`), and XcodeGen
(`brew install xcodegen`).

```sh
cd ios && xcodegen && open SFDesk.xcodeproj
```

In Xcode, pick your team under Signing & Capabilities, connect your iPhone (or pick a simulator), and click
Run. Each build first runs `build-core.sh`, so it always has the current `src/` and `public/`.

The first time you run a build from your own Mac on an iPhone, you have to trust it on the phone. On the
iPhone, go to Settings > General > VPN & Device Management.

To share builds with others, use TestFlight or the company's device management. Both need the company's
Apple Developer account.

## Test on the Mac, without an iPhone

`build-mac-test.sh` compiles the same Swift host (all but `App/iOSApp.swift`) as a Mac app with a
phone-sized window:

```sh
ios/build-mac-test.sh --run        # opens it; Connect signs in with the Salesforce login page
ios/build-mac-test.sh --selftest   # with the Salesforce CLI's token: opens each tab, calls the API, exports
                                   # to Excel, and saves screenshots and results.json in ios/build/selftest
```

Add `SFDESK_NO_CALENDAR=1` to leave the calendar out. The test app keeps its own database, in Application
Support/SF Desk iOS Test.

## Other scripts

- `make-icon.sh` renders `SFDesk/AppIcon.svg` as the app icon.
- `test/bundle-in-sandbox.mjs` runs the core bundle in a bare JavaScript sandbox and saves the same API
  answers as `scripts/api-snapshot.mjs`, so the two can be compared.
