# SF Desk security

How SF Desk works, what data it touches, where that data is kept, and how it is protected. It is written for
users and for IT or security reviewers. For setup, see [INSTALL.md](INSTALL.md); for the Outlook add-in, see
[OUTLOOK.md](OUTLOOK.md).

## Summary

- SF Desk runs entirely on your own computer or iPad. There is no SF Desk server, cloud service or
  third-party service in between: it talks directly to Salesforce (and, if you turn it on, Microsoft 365)
  over HTTPS.
- It signs in as **you**, so Salesforce's own sharing rules, profiles and field-level security decide what
  it can see and change. It cannot see or do anything your Salesforce user can't.
- It only writes to Salesforce when you click **Save**, **Add**, **Create** or confirm a bulk change, and
  it only writes a fixed set of fields.
- On the desktop, its web server only answers on this computer (`localhost`); other computers on the
  network can't reach it.
- It keeps a local copy of the accounts and opportunities you've loaded, so you can browse them offline.
  That copy is protected by your computer account and disk encryption (FileVault, BitLocker), not by SF Desk.

## How it works

| Client | What runs | Where the page is shown |
| --- | --- | --- |
| Mac app | A small Node.js server inside **SF Desk.app**, on `http://localhost:3000` | The app's own window (WebKit) |
| Windows | The same Node.js server, installed per user with no admin rights | Microsoft Edge in app mode, with its own profile |
| From a Git checkout | `npm start` | Any browser on the same computer |
| iPad / iPhone | The same core code in JavaScriptCore, inside the app; there is no network server | The app's own window, at `sfdesk://app/` |

In every client the page asks the local core for data, and the core calls the Salesforce REST API with your
access token. The page never holds the token.

## Signing in

### Salesforce CLI login (desktop default)

With no `SF_CLIENT_ID` set, SF Desk borrows the login you already have in the Salesforce CLI (`sf`):

- You sign in through the CLI's normal browser flow (`sf org login web`), so SSO, MFA and your company's
  sign-in policies apply as usual.
- SF Desk runs `sf org display` (or `sf org auth show-access-token`) to get a short-lived access token,
  and asks again when it expires. The CLI keeps its own login in its own store; SF Desk doesn't copy it.
- **Disconnect** signs SF Desk out only. Your CLI login stays until you run `sf org logout`.

### Your own connected app (optional)

With `SF_CLIENT_ID` set, SF Desk uses the OAuth web server flow with PKCE (S256), a random `state` value
checked on return, and the callback `http://localhost:3000/oauth/callback`. **Disconnect** revokes the token
with Salesforce.

### iPad and iPhone

The iOS app signs in with the Salesforce CLI's public client (`PlatformCLI`) and PKCE. The sign-in page
(your My Domain, then SSO) is shown in the app; the redirect to `http://localhost:1717/OauthRedirect` is
caught by the app and never loaded. The refresh token is kept in the iOS Keychain as
*accessible after first unlock, this device only*, so it isn't included in backups or moved to another
device. Signing out revokes it with Salesforce and deletes it.

### Microsoft 365 (optional)

Only for reading the new Outlook's calendar on Windows, and for marking meetings that have a Deal Support.
It uses Microsoft's device-code sign-in with Microsoft's own Graph Command Line Tools client, so there's no
app registration. Your tenant may require an admin to approve it. The only Microsoft 365 write is adding the
Deal Support category to your own meetings, and only after you ask for it.

## Where tokens and data are kept

| What | Where | Protection |
| --- | --- | --- |
| Salesforce access token (desktop) | Server memory, for the session only | Never written to disk; quitting SF Desk forgets it |
| Salesforce login (CLI) | The Salesforce CLI's own store | Managed by the CLI |
| Salesforce refresh token (iOS) | iOS Keychain | This device only, after first unlock |
| Microsoft 365 refresh token | `graph-token.json` in the data folder | File readable by your user only (`0600`) |
| Local copy of records | `data/sf-desk.db` (SQLite) in the data folder | Your user account and disk encryption |
| Outlook add-in certificate | `certs/` in the data folder | See [the Outlook certificate](#the-outlook-add-in-certificate) |
| Server log | `~/Library/Logs/SF Desk/server.log` (Mac), `logs\server.log` (Windows) | Your user account; no tokens are logged |

The data folder is `~/Library/Application Support/SF Desk` on a Mac, `%LOCALAPPDATA%\SF Desk` on Windows,
and the app's own Application Support folder on iOS.

### What the local database holds

- Accounts and opportunities you've loaded: the fields SF Desk shows, plus owner and modified date.
- The accounts and opportunities you've hidden in SF Desk. Hiding is local only and never sent to Salesforce.
- Which calendar meetings you've linked to a Deal Support or marked *No Deal Support needed* (event IDs).
- Org settings it worked out (which fields are Lead SE, your BOATs, your team) and the last My Time load,
  so pages still show something offline.

Deal Supports are otherwise read live and not stored. Edits go straight to Salesforce; nothing is queued
locally. To clear the local copy, quit SF Desk and delete `sf-desk.db`. It is rebuilt as you browse.

### Calendar

Time Entry reads your calendar on your own computer: through macOS Calendar access (EventKit, which macOS asks
you to allow), classic Outlook's COM API on Windows, or Microsoft Graph if you've signed in to Microsoft 365.
Meetings are read when you open the tab and are not stored, apart from the links described above.

## How the local server is protected

The desktop server is a web server, so it is locked down against other computers and against other web pages
open in your browser:

- **Local only.** It listens on `localhost` (ports 3000 and, for Outlook, 3443), not on the network.
- **Host check.** It refuses any request whose `Host` isn't `localhost`, `127.0.0.1` or `[::1]` on its own
  ports (HTTP 421). This stops *DNS rebinding*, where a malicious website points its own domain name at your
  computer to talk to local servers.
- **Write guard.** Every write to the API must carry an `X-SFDesk: 1` header. Browsers don't let other sites
  send custom headers without the server's permission, and SF Desk gives none, so another site can't make
  changes through it (cross-site request forgery).
- **Sessions.** The session cookie is `HttpOnly`, so page scripts can't read it. On HTTP it is
  `SameSite=Lax`; on HTTPS (Outlook) it is `Secure` and `SameSite=None`, because Outlook frames the page. The
  cookie signing secret is random and new each time the server starts.
- **Small requests.** Request bodies are limited to 100 KB.
- **The window stays local.** The Mac app only shows local pages in its window; any other link opens in your
  default browser.

The iOS app has no server or port. The page is served to its own web view through a private `sfdesk://`
scheme.

## What SF Desk sends to Salesforce

- **Your permissions.** Every call runs as your user, so Salesforce enforces sharing, profiles and
  field-level security. Fields you can't edit are shown greyed out, and Salesforce rejects them anyway.
- **Fixed fields.** The server only writes the account and opportunity fields it lists (`ACCOUNT_FIELDS` and
  `OPP_FIELDS` in `src/core.js`), and Deal Support and TES Request fields from those objects' own layouts.
  A request to change any other account or opportunity field is refused.
- **No overwriting others' changes.** When you save, SF Desk checks the record's last-modified time. If
  someone changed it after you loaded it, the save is refused rather than overwriting their work.
- **Safe queries.** Record IDs must be valid Salesforce IDs, and every text value placed in a SOQL query is
  escaped, so search text can't change a query.
- **Bulk changes ask first.** Changing the SE or sales rep on many accounts, or moving time between
  opportunities, shows a summary to confirm first.

## Showing data safely

- Record values are put on the page as text, never as HTML, so a field containing `<script>` is shown as
  those characters and never run. The page's only HTML is its own built-in icons.
- **Export to Excel** writes record values as typed cells (text, numbers, dates), never as formulas, so a
  value starting with `=` can't run as a formula when the file is opened. The only formulas are the SUM
  totals SF Desk adds itself.
- The page loads no third-party scripts. The only exception is the Outlook task pane, which loads Microsoft's
  Office.js from `appsforoffice.microsoft.com`, as all Outlook add-ins do.

## The Outlook add-in certificate

Outlook only loads add-ins over HTTPS, so **Set Up Outlook Add-in...** (or `scripts/outlook-cert.sh --trust`)
makes a certificate for `https://localhost:3443` and asks macOS to trust it:

- It makes a private certificate authority, "SF Desk local CA", which is **limited to `localhost` and
  `127.0.0.1`** (an X.509 *name constraint*, marked critical). macOS and browsers won't accept it for any
  other site, even if it were misused.
- The authority's private key is **deleted** as soon as it has signed the localhost certificate, so nothing
  can make new certificates from it. Only the localhost certificate and its key are kept, in `certs/`.
- Older versions kept the authority's key and had no limit. The script notices such an authority, replaces
  it, and with `--trust` removes the old one from your login keychain.
- The certificate lasts 825 days. Renewing it makes a new authority, which macOS asks you to trust again.

The certificate is only needed for the Outlook add-in. Without it, SF Desk doesn't listen on 3443.

## Dedicated Microsoft Graph and Salesforce apps

Today SF Desk signs in through two clients that already exist and are shared with other tools: Microsoft's
"Microsoft Graph Command Line Tools" for Microsoft 365, and the Salesforce CLI's `PlatformCLI` for Salesforce
on iOS (and on the desktop through the CLI login). This works without setup, but IT can't tell SF Desk apart
from those tools, or control it separately. Registering an SF Desk app with each service fixes that. SF Desk
already supports both: set `SF_DESK_GRAPH_CLIENT_ID` and `SF_DESK_GRAPH_TENANT` for Microsoft Graph, and
`SF_CLIENT_ID` for Salesforce on the desktop. The iOS app needs a small change to use its own Salesforce app
(see below).

| | Shared clients (today) | Dedicated SF Desk apps |
| --- | --- | --- |
| Who can sign in | Anyone who can use the shared tool | Only users or groups IT assigns |
| Permissions granted | Shared with every user of that tool | Granted to SF Desk alone, and only what it needs |
| Sign-in logs and audits | Show "Microsoft Graph Command Line Tools" or "Salesforce CLI" | Show "SF Desk" |
| Policies (MFA, device, network, session length) | Whatever applies to the shared tool | Set for SF Desk on its own |
| Cutting off access | Affects everyone using the shared tool | Turn off or revoke SF Desk only |

### Microsoft Graph: an SF Desk app registration in Entra ID

The request for IT is in [MS-GRAPH-IT-REQUEST.md](MS-GRAPH-IT-REQUEST.md). A dedicated registration would
make Microsoft 365 access safer in these ways:

- **Permissions aren't shared.** Approving `Calendars.ReadWrite` for Microsoft's Graph Command Line Tools
  also grants it to everyone using Microsoft Graph PowerShell and the Graph CLI with that client. An SF Desk
  registration keeps that permission to SF Desk.
- **Least privilege.** Only the delegated permissions `User.Read`, `Calendars.ReadWrite` and
  `offline_access`, with no application permissions. SF Desk acts only as the signed-in user, on that user's
  own calendar. It asks for `Calendars.Read` alone until marking meetings is turned on, and its only write is
  a meeting's `categories` field.
- **Only the right people.** A single-tenant registration with *assignment required* lets IT limit it to
  the Solutions Engineering team.
- **Targeted Conditional Access.** IT can apply policies to SF Desk itself, such as requiring a managed or
  compliant device, MFA, or sign-in from the corporate network.
- **No secrets.** It is a public client (*Allow public client flows*), so there is no client secret or
  certificate to store on users' computers. Each user signs in with their own account, including MFA.
- **Visible and revocable.** Entra ID's sign-in logs and enterprise applications list show "SF Desk", so IT
  can review who uses it, and disable it or revoke its sessions in one place without affecting other tools.

The registration could also move sign-in from the device code flow to an authorization code flow with PKCE
in the system browser, which Microsoft recommends where it works. Many organizations block the device code
flow with Conditional Access because it can be used in phishing; a dedicated app lets SF Desk follow that
policy.

### Salesforce: an SF Desk connected app or External Client App

A Salesforce admin creates an External Client App (or a classic connected app) for SF Desk. Its settings are
in [README.md](README.md#option-b-create-an-app-in-salesforce). It would make Salesforce access safer in
these ways:

- **Admin-approved users only.** Set *Permitted Users* to *Admin approved users are pre-authorized*, then
  allow it through a permission set for the SE team. Other users can't sign in to SF Desk at all.
- **Only the scopes SF Desk needs.** `api` and `refresh_token` only, without `web` or `full`. The CLI's own
  app asks for more because it is a general developer tool.
- **PKCE, no secret.** The app requires PKCE and needs no client secret, so nothing secret ships inside SF
  Desk. A stolen authorization code is useless without the code verifier that only the app has.
- **Session and token policies.** Admins can set how long refresh tokens last (for example, expire after 90
  days or when unused), require a high-assurance (MFA) session, apply IP ranges, and set session timeouts for
  SF Desk alone.
- **Separate from developer tools.** SF Desk would no longer borrow the Salesforce CLI's login, so it
  wouldn't need the CLI installed, and limiting SF Desk wouldn't affect developers using the CLI, or the
  other way round.
- **Visible and revocable.** Login History and Connected Apps OAuth Usage show "SF Desk". An admin can see
  who uses it and revoke all its tokens, or one user's, without touching anything else.

On iOS, the dedicated app would also change how sign-in is shown. The sign-in page would open in
`ASWebAuthenticationSession`, the system's sign-in browser, with an `sfdesk://` callback, instead of a web
view inside the app:

- **The app never sees the sign-in page.** Your password, passkey and MFA go to Salesforce and Microsoft
  Entra in the system browser, which SF Desk can't read or change.
- **Single sign-on works.** The system browser shares the device's Microsoft and Salesforce sessions, so
  users aren't asked for their password or passkey again. Phishing-resistant passkeys work as designed.
- **The callback can't be taken over.** Only SF Desk receives its own callback, checked with `state` and
  PKCE.

### Standards and guidance these follow

- **OAuth 2.0 for Native Apps (RFC 8252):** apps sign users in through the system browser, not an embedded
  web view, and use PKCE.
- **PKCE (RFC 7636):** stops stolen authorization codes being used.
- **OAuth 2.0 Security Best Current Practice (RFC 9700):** PKCE for every client, no secrets in public
  clients, refresh tokens that can be revoked, and narrow scopes.
- **Microsoft identity platform guidance:** a registration for each app, least-privilege delegated
  permissions, admin consent, user assignment and Conditional Access.
- **Salesforce connected app guidance:** admin-approved users, minimal OAuth scopes, PKCE, and refresh token
  and session policies set for each app.

## Known limitations

These are accepted trade-offs for a single-user desktop tool. Each depends on someone already having access
to your computer or user account:

- **The local database isn't encrypted by SF Desk.** It relies on your user account and disk encryption.
  Keep FileVault (Mac) or BitLocker (Windows) on.
- **Local programs can use the server.** Another program running as you on the same computer could call the
  local API, the same way it could run `sf` with your CLI login. Browser pages from other sites can't.
- **The HTTP port is not encrypted.** Traffic on `http://localhost:3000` never leaves your computer, so
  there's nothing on the network to read; HTTPS is used where Outlook needs it.
- **The Mac app is ad-hoc signed**, not signed with an Apple Developer ID or notarized, so macOS asks you to
  allow it on first launch (see [INSTALL.md](INSTALL.md)).
- **iOS uses the Salesforce CLI's public client.** It works without a connected app of your own, but
  Salesforce admins see sign-ins as the Salesforce CLI. A dedicated connected app would let them manage SF
  Desk separately (see [Dedicated Microsoft Graph and Salesforce apps](#dedicated-microsoft-graph-and-salesforce-apps)).
- **The iOS sign-in page doesn't use the device's single sign-on.** The page is shown inside the app, so
  Microsoft Entra may ask for your password or passkey again. The dedicated Salesforce app's system-browser
  sign-in fixes this.
- **Microsoft 365 uses Microsoft's shared Graph Command Line Tools client** until IT registers an SF Desk
  app, so its permissions are shared with that tool's other users.
- **Development builds log more.** Debug builds of the iOS app log connection errors and allow the Web
  Inspector; use a Release build for everyday use.
- **Windows has no Outlook add-in certificate yet**, so the add-in is Mac-only.

## Reporting a problem

If you find a security issue, tell the SF Desk maintainer directly rather than opening a public issue. To
cut off SF Desk's access at once: click **Disconnect**, run `sf org logout` for the CLI login, and in
Salesforce go to **Settings > Connected Apps OAuth Usage** (or have an admin do it) to revoke the session.
On iOS, sign out in the app, or delete the app to remove its Keychain entry.
