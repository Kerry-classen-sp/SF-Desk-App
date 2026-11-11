# SF Desk for iPad

The same app as the Mac's, without the Outlook add-in. It's for iPad only (`TARGETED_DEVICE_FAMILY` 2 in
`ios/project.yml`); Apple silicon Macs can run it too. Nothing in Salesforce needs setting up for it.

## How it works

- **Shared core:** the desktop server's API (`src/core.js`, `src/router.js`, `src/store.js`, `src/sha1.js`)
  runs in JavaScriptCore. `ios/build-core.sh` bundles it with `ios/SFDesk/Host/host.js` into
  `ios/SFDesk/Generated/core-bundle.js`. A change to the API is made once, in `src/`, for both apps.
- **Page:** `public/` (copied to `ios/SFDesk/Generated/web`), unchanged, in a web view at `sfdesk://app/`.
  `WebHost.swift` serves its files and answers its `/api/...` calls through the core, as the desktop server
  does.
- **Native parts (Swift, `ios/SFDesk/Host`):**

  | File | What it does |
  | --- | --- |
  | `SalesforceAuth.swift` | Sign-in and token refresh |
  | `Keychain.swift` | Keeps the saved login |
  | `SQLiteStore.swift` | The local database (offline copies, hidden records, event marks, filters) |
  | `CoreRuntime.swift` | Salesforce calls through URLSession, which a page can't make itself |
  | `CalendarReader.swift` | The phone's calendars, through EventKit |

- **Salesforce sign-in:** uses the Salesforce CLI's connected app (`PlatformCLI`, which every org has), with
  PKCE. The org's login page (`SFDeskLoginURL` in `ios/SFDesk/Info.plist`, the My Domain) opens in the app and
  continues to SSO. The refresh token stays in the Keychain. **Disconnect** revokes it.
- **Calendar:** Time Entry reads the Exchange account added under Settings > Calendar > Accounts on the
  device. Other calendars (iCloud, Google...) aren't listed or read.

## Build for an iPad

You need Xcode, with its license accepted (`sudo xcodebuild -license accept`), and XcodeGen
(`brew install xcodegen`).

```sh
cd ios && xcodegen && open SFDesk.xcodeproj
```

In Xcode, pick your team under Signing & Capabilities, connect your iPad (or pick a simulator), and click
Run. Each build first runs `ios/build-core.sh`, so it always has the current `src/` and `public/`.

Or, with an iPad connected, `ios/build-device.sh` builds and installs it in one go. It first sets
the app's version and build number (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `ios/project.yml`)
from `package.json`, so it matches the desktop apps; `scripts/build-apps.sh` keeps them in step too.

The first time you run a build from your own Mac on an iPad, you have to trust it on the iPad. On the
iPad, go to Settings > General > VPN & Device Management.

## TestFlight

`ios/testflight.sh` archives a Release build and uploads it to App Store Connect, with the version and
build number from `package.json`. Release builds leave out the Web Inspector and the debug logging, and
the app carries a privacy manifest (`ios/SFDesk/PrivacyInfo.xcprivacy`: no tracking, nothing collected).

Once, before the first upload:

1. Be in the Apple Developer Program team set in `ios/project.yml` (`DEVELOPMENT_TEAM`), and sign in to it in
   Xcode > Settings > Accounts. For unattended uploads, make an App Store Connect API key (Users and Access >
   Integrations) and set `ASC_KEY_PATH`, `ASC_KEY_ID` and `ASC_ISSUER_ID` instead.
2. In [App Store Connect](https://appstoreconnect.apple.com), Apps > + > New App: platform iOS, a name
   (unique on the App Store, e.g. "SF Desk for SailPoint"), bundle ID `com.sailpoint.sfdesk` (registered by
   the first export), SKU `sf-desk`, and Full Access for users.
3. Under TestFlight, make an internal testing group and add the testers. Internal testers must be users of
   the App Store Connect team; builds reach them without Apple's review. External testers (anyone else, by
   email or public link) need Beta App Review, which needs a way for the reviewer to sign in. SF Desk only
   signs in with a SailPoint Salesforce login, so say so in the review notes or keep to internal testers.

Then, for each build:

```sh
scripts/build-apps.sh   # a new build number (App Store Connect refuses one it already has)
ios/testflight.sh       # archive and upload; ios/testflight.sh --export only makes the .ipa
```

The build shows under TestFlight after Apple processes it (10 to 30 minutes). Testers install the TestFlight
app and accept the invitation. Encryption is declared exempt (`ITSAppUsesNonExemptEncryption`: SF Desk only
uses the encryption built into iOS), so no export compliance questions are asked. See
[EXPORT-COMPLIANCE.md](EXPORT-COMPLIANCE.md) for the reasons and the answers if App Store Connect asks.

## Test on the Mac, without an iPad

`ios/build-mac-test.sh` compiles the same Swift host (all but `ios/SFDesk/App/iOSApp.swift`) as a Mac app with a
phone-sized window:

```sh
ios/build-mac-test.sh --run        # opens it; Connect signs in with the Salesforce login page
ios/build-mac-test.sh --selftest   # with the Salesforce CLI's token: opens each tab, calls the API, exports
                                   # to Excel, and saves screenshots and results.json in ios/build/selftest
```

Add `SFDESK_NO_CALENDAR=1` to leave the calendar out. The test app keeps its own database, in Application
Support/SF Desk iOS Test.

## Other scripts

- `ios/make-icon.sh` renders `ios/SFDesk/AppIcon.svg` as the app icon.
- `ios/test/bundle-in-sandbox.mjs` runs the core bundle in a bare JavaScript sandbox and saves the same API
  answers as `scripts/api-snapshot.mjs`, so the two can be compared.
