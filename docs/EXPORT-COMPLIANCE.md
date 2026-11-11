# SF Desk for iPad: encryption and export compliance

What App Store Connect asks about encryption for each TestFlight or App Store build, the answers for SF Desk,
and the reasons. It covers the iOS app (`ios/`) only. The Mac and Windows apps aren't distributed through
Apple, so this doesn't apply to them.

## Summary

SF Desk uses only the encryption built into iOS: HTTPS (TLS) for its Salesforce calls, the Keychain for the
saved login, and iOS Data Protection for its files. It has no encryption code of its own and no third-party
encryption library. Under Apple's guidance, an app whose only encryption is the operating system's is exempt
from the export documentation upload, so no documents need to be sent to Apple.

The app declares this in `ios/SFDesk/Info.plist`:

```xml
<key>ITSAppUsesNonExemptEncryption</key><false/>
```

With that key, App Store Connect doesn't ask the encryption questions for each build, and the build goes
straight to TestFlight once processed. No encryption registration (ERN) or CCATS is needed, and nothing has
to be uploaded under App Store Connect > App Information > App Encryption Documentation.

## If App Store Connect asks

If a build is ever uploaded without the key, App Store Connect asks under the build's export compliance (the
wording changes from time to time):

| Question | Answer |
| --- | --- |
| Does your app use encryption? | Yes: it makes HTTPS calls. |
| Which type of encryption algorithms does your app implement? | None of the algorithms mentioned above (it only uses or accesses the encryption in Apple's operating system) |

Answering this way gives the same result as the key: no documentation is needed.

## What the app uses

Everything the iOS app does that touches cryptography:

| Use | Where | How | Is it encryption? |
| --- | --- | --- | --- |
| Calls to Salesforce (REST API, OAuth token and revoke) | `ios/SFDesk/Host/CoreRuntime.swift`, `SalesforceAuth.swift` | `URLSession` over HTTPS | Yes, the operating system's (TLS) |
| Salesforce sign-in page and SSO | `SalesforceAuth.swift` | `WKWebView` over HTTPS | Yes, the operating system's (TLS) |
| Saved login (refresh token) | `ios/SFDesk/Host/Keychain.swift` | Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | Yes, the operating system's (Keychain) |
| Local database (offline copies, hidden records, filters) | `ios/SFDesk/Host/SQLiteStore.swift` | Plain SQLite file in the app's container, protected by iOS Data Protection | Yes, the operating system's (Data Protection); the app adds none |
| PKCE sign-in check (RFC 7636) | `SalesforceAuth.swift` | `SecRandomCopyBytes` for the verifier, CryptoKit `SHA256` for the challenge | No: random numbers and a hash, used for authentication |
| IDs for calendar events and meetings | `src/sha1.js`, `src/core.js`, `ios/SFDesk/Host/host.js` | SHA-1 of the event's ID and time, to make a stable key | No: a hash, used as an identifier |

What isn't there:

- No encryption or decryption of data by the app itself, and no algorithm written into the app (no AES,
  RSA, elliptic curve or other cipher code, and no OpenSSL, SQLCipher, libsodium or similar).
- No end-to-end encryption, VPN, encrypted messaging or file encryption feature.
- No plain HTTP: the app has no App Transport Security exceptions (`NSAppTransportSecurity`), so iOS refuses
  any connection that isn't HTTPS. The sign-in redirect (`http://localhost:1717/OauthRedirect`, the
  Salesforce CLI's) is caught in the sign-in view and never loaded.

Hashing, random numbers and authentication aren't encryption for data confidentiality under the US Export
Administration Regulations (Category 5, Part 2), and HTTPS and the Keychain are the operating system's.

## When to look at this again

The answers stay right while the app only uses the operating system's encryption. Look again (and probably set
`ITSAppUsesNonExemptEncryption` to `true` and answer the questions in App Store Connect) if a change adds:

- an encryption library or encryption code of its own, e.g. an encrypted database such as SQLCipher, or
  encrypting exports or cached data with CryptoKit `AES` or `ChaChaPoly`;
- a protocol the app implements itself rather than iOS, e.g. its own TLS, SSH or a VPN;
- a third-party SDK that brings its own encryption (check its export compliance notes).

To check a build, search the app's sources for encryption APIs:

```sh
rg -n "CryptoKit|CommonCrypto|CCCrypt|SecKeyCreate|AES|ChaChaPoly|SQLCipher|NSAppTransportSecurity" ios/SFDesk src
```

Today the only results are CryptoKit (for the SHA-256 PKCE hash) and none of the others.

## Who answers for it

This is the app's technical account, for App Store Connect and for reviewers. The legal export classification
of a SailPoint product belongs to SailPoint's trade compliance team. If the app moves to the company's Apple
Developer account or is distributed beyond SailPoint employees, ask them to confirm it.

References: Apple, [Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
and [ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).
