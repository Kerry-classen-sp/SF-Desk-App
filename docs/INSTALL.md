# Installing SF Desk on a SailPoint Mac

SF Desk runs entirely on your Mac. It signs in to Salesforce as you, through the Salesforce CLI, and
only sees and changes what your own Salesforce user can. Nothing is hosted anywhere else.

## The SF Desk app (recommended)

**SF Desk.app** has everything inside it: the SF Desk server, Node.js and its dependencies. There's
nothing else to install and no Terminal window to keep open.

1. **Get `SF-Desk.dmg`** from Kerry Classen and double-click it. In the window that opens, drag **SF Desk**
   onto the **Applications** folder. The window also has short install instructions ("Read Me First"), the
   Outlook add-in guide and the full SF Desk guide. Then eject the disk image. (`SF-Desk-app.zip` has just the app:
   double-click it and drag **SF Desk** into Applications.)
2. **Open it once with Open Anyway.** The app isn't signed by Apple, so the first time macOS says it
   can't verify the developer. Click **Done**, open **System Settings > Privacy & Security**, scroll
   down, click **Open Anyway** next to "SF Desk" and confirm with your password. (On some macOS versions
   right-click > **Open** > **Open** works too.) You only do this once per new version.
3. **Follow its prompts.** The first time, SF Desk:
   - copies your settings and data from an earlier install (`~/SF-Desk`) or Git checkout, if you have one;
   - offers to install the Salesforce CLI if it can't find one: with Homebrew (`brew install sf`) if you
     have it, else Salesforce's own download (no admin rights needed);
   - opens your browser to sign in to `sailpoint.my.salesforce.com` with SSO, if the CLI isn't signed in.
4. **Click Connect**, then open **Time Entry** and choose **Sign in to Microsoft 365...** in the list at
   the top. Microsoft's sign-in opens in a sheet on the SF Desk window with the code already entered;
   pick or type your SailPoint account. See [Your Microsoft 365 calendar](#your-microsoft-365-calendar).

Keep SF Desk in the Dock (right-click its icon > **Options > Keep in Dock**). Closing the window keeps it
running in the background, so the Outlook add-in keeps working; click the Dock icon to bring it back, and
quit it (**SF Desk > Quit SF Desk**) to stop it. The app runs its own server, so stop any SF Desk running
from a Terminal window or a checkout first; otherwise the app reports that its server couldn't start.

**Your data** lives in `~/Library/Application Support/SF Desk` (**Help > Show Data Folder**): `.env` for
settings (open it from that folder in a text editor, then **File > Restart Server**), `data/` for the local copy of
your records, `certs/` for the Outlook add-in's certificate and `sf-cli/` if the app downloaded the CLI.
To update, replace the app with the new one; all of that is kept. The server's log is in
`~/Library/Logs/SF Desk` (**Help > Show Server Log**).

**Outlook add-in:** choose **SF Desk > Set Up Outlook Add-in...** (or say yes when the app offers it the
first time). It trusts its HTTPS certificate (macOS asks for your password), saves the add-in file to
Downloads and opens Outlook's add-in page; there, choose **My add-ins > Custom Addins > Add a custom
add-in > Add from File...** and pick `sf-desk-outlook.xml`. See [OUTLOOK.md](OUTLOOK.md).

**Uninstalling:** quit SF Desk, delete it from Applications, and delete
`~/Library/Application Support/SF Desk` and `~/Library/Logs/SF Desk`.

### Building the app

To build everything that's handed out (the Mac app and disk image, the Mac Terminal installer and both
Windows downloads), run `scripts/build-apps.sh` on a Mac with the GitHub CLI (`gh`) signed in. It does the
whole release: `git pull --tags`, commits anything uncommitted, raises the build number in `package.json`
(the version only changes when you change it), merges that into `main` through a pull request, tags it
`v<version>-build.<build>` and builds from `main`, so every download names its build. It uses the
checkout's `node_modules` (checked against `package-lock.json`), so it works on the SailPoint network;
`--npm` installs them from the registry instead. The steps below are the builds it runs.

The app has to be compiled on a Mac with the Xcode Command Line Tools (`xcode-select --install`). Its
`node_modules` and Node.js come from the same download as the Terminal installer below, which can be
built anywhere npm and nodejs.org are reachable. So:

1. Anywhere (e.g. in the cloud): `scripts/build-mac-package.sh` writes `dist/SF-Desk-mac.zip`. Only
   redo this when `package-lock.json` changes.
2. On a Mac: `scripts/build-mac-app.sh --from path/to/SF-Desk-mac.zip`. It takes SF Desk itself from the
   checkout's current commit, compiles the app for Apple Silicon and Intel, puts the server, its
   `node_modules` and Node.js inside, signs it ad hoc, and writes `dist/SF Desk.app`, `dist/SF-Desk-app.zip`
   and `dist/SF-Desk.dmg`. The disk image, the file to hand out, holds the app, a shortcut to Applications
   and, as web pages made by `scripts/md-to-html.mjs`, a short install guide (`docs/MAC-READ-ME-FIRST.md`),
   the README and OUTLOOK.md.

With `node_modules` in your checkout and a nodejs.org build of Node, `scripts/build-mac-app.sh --node
/path/to/node` skips step 1. The bundled Node is for Apple Silicon; on an Intel Mac the app uses Node.js
22 or newer installed from nodejs.org instead.

## Quick install with the Terminal installer

Get `SF-Desk-mac.zip` from Kerry Classen. It bundles everything SF Desk needs on an Apple Silicon Mac
(Node.js and all dependencies), so there's no npm, Git or Node install, and Cisco Umbrella's npm
block doesn't matter.

1. **Unzip the download** and double-click **Install SF Desk.command**. If macOS says it can't verify
   the developer, click **Done**, then go to **System Settings > Privacy & Security**, scroll down,
   click **Open Anyway** next to the file and confirm. (Right-click > **Open** also works on some
   macOS versions.)
2. **Follow the Terminal window.** The installer:
   - copies SF Desk into `~/SF-Desk`;
   - installs the Salesforce CLI if you don't have it: with Homebrew (`brew install sf`) if you have it,
     else downloaded from Salesforce into `~/SF-Desk/sf-cli` (no admin rights needed);
   - opens your browser to sign in to `sailpoint.my.salesforce.com` with SSO, once;
   - puts **Start SF Desk** on your Desktop and starts SF Desk.
3. **Click Connect.** SF Desk opens at http://localhost:3000. Then sign in to Microsoft 365 in **Time
   Entry** (see [Your Microsoft 365 calendar](#your-microsoft-365-calendar)).

From then on, double-click **Start SF Desk** on your Desktop. Keep its Terminal window open while you
use SF Desk, and close it to stop SF Desk. To update, unzip a newer download and run the installer
again; your settings, login and data in `~/SF-Desk` are kept. To uninstall, delete `~/SF-Desk` and the
Desktop launcher.

On an Intel Mac, install Node.js 22 or newer from https://nodejs.org first; the installer uses it
instead of the bundled one.

### Building the download

From a checkout of this repo, on any machine that can reach the npm registry and nodejs.org (so not
on the SailPoint network), run:

```bash
scripts/build-mac-package.sh            # or: scripts/build-mac-package.sh v26.11.1
```

It writes `dist/SF-Desk-mac.zip` from the current commit, with `node_modules` from the lockfile and
Node.js for Apple Silicon (checked against nodejs.org's checksums). Rebuild it whenever you want to
hand out a new version.

## Manual install

Use this if you'd rather work from a Git checkout, for example to change the code. It takes about
20 minutes, most of it waiting on installers.

### What you need

| Requirement | Why | Check |
|---|---|---|
| A Mac on macOS 14 (Sonoma) or newer, Apple Silicon or Intel | Built and tested on Apple Silicon (arm64) | Apple menu > **About This Mac** |
| Node.js 22 or newer | Runs the app (built and tested on Node 26) | `node -v` |
| Git (or GitHub Desktop) and read access to `Kerry-classen-sp/SF-Desk-App` | To get the code; ask Kerry Classen for access | `git --version` |
| Salesforce CLI (`sf`) | SF Desk borrows its login, because we can't create our own Salesforce app | `sf --version` |
| A Salesforce login to `sailpoint.my.salesforce.com` with API access | Your normal SSO login is fine | |
| Your SailPoint Microsoft 365 account | The **Time Entry** tab reads your meetings from it | You can sign in to Outlook on the web |

Run every command below in **Terminal.app** (Applications > Utilities > Terminal).

### 1. Install the tools

#### Node.js

Download the macOS installer (`.pkg`) for the current LTS or newer from https://nodejs.org and run it.
Then open a new Terminal window and check:

```bash
node -v    # v22.0.0 or newer
```

#### Salesforce CLI

With Homebrew, `brew install sf`. Otherwise download the macOS installer (`.pkg`) from
https://developer.salesforce.com/tools/salesforcecli and run it.

Don't use `npm install -g @salesforce/cli`. Cisco Umbrella on SailPoint Macs blocks the npm registry
(`registry.npmjs.org`), so that fails.

```bash
sf --version
```

### 2. Sign in to Salesforce with the CLI

```bash
sf org login web --instance-url https://sailpoint.my.salesforce.com --set-default
```

A browser window opens to the SailPoint Salesforce login. Sign in with SSO as usual, allow access, and
return to Terminal when it says you're logged in. You only do this once; the CLI keeps you signed in.

Check it worked:

```bash
sf org display
```

It should show `sailpoint.my.salesforce.com` as the Instance Url and your username. If you named the
login with `--alias`, you'll set that alias in `.env` in step 4.

### 3. Get the code and its dependencies

```bash
cd ~/Documents
git clone https://github.com/Kerry-classen-sp/SF-Desk-App.git SF-Desk
cd SF-Desk
```

(With GitHub Desktop: **File > Clone Repository**, then `cd` into the folder it made.)

SF Desk needs four npm packages: `express`, `express-session`, `dotenv` and `better-sqlite3`. The
last one is a native module (SQLite), but it ships prebuilt binaries for Apple Silicon and Intel
Macs, so nothing gets compiled.

**If the npm registry is reachable** (for example off the corporate network):

```bash
npm install
```

**On the SailPoint network**, where Umbrella blocks `registry.npmjs.org`, take the ready-made
`node_modules` folder from the `build/local-deps-75e52w` branch instead. GitHub isn't blocked, so this
works anywhere:

```bash
git fetch origin build/local-deps-75e52w
git archive origin/build/local-deps-75e52w node_modules | tar -x
```

This unpacks `node_modules` into the project folder without switching branches (git ignores the
folder, so it never shows up as a change). To check it worked:

```bash
node -e "require('better-sqlite3'); console.log('ok')"
```

That branch matches the current `package-lock.json`. If a future update changes `package-lock.json`,
the branch needs rebuilding before this step will work again; ask in the SF-Desk project.

### 4. Configure

```bash
cp .env.example .env
```

For a SailPoint install you normally don't change anything. Leave `SF_CLIENT_ID` empty so SF Desk uses
your CLI login. Only set these if they apply:

- `SF_TARGET_ORG=` the alias or username, if you used `--alias` in step 2 or have more than one org
  logged in to the CLI.
- `SF_CLI_PATH=` the full path from `which sf`, if SF Desk says it can't find the Salesforce CLI.
- `PORT=` another port, if something else already uses 3000.

### 5. Start SF Desk

From Terminal.app, in the project folder:

```bash
npm start
```

You'll see `SF Desk running at http://localhost:3000`. Open that address in your browser and click
**Connect**. Keep the Terminal window open while you use the app; press **Ctrl+C** in it to stop SF Desk.

## Your Microsoft 365 calendar

**Time Entry** reads your meetings from Microsoft 365 through Microsoft Graph, the same on the Mac app, a
Terminal or manual install, Windows and the iPad. It works with any Outlook (new, classic, on the web) and
doesn't need the calendar set up on the computer. The other choice in its list is **Salesforce events**.

1. Open **Time Entry** and choose **Sign in to Microsoft 365...** in the list at the top.
2. SF Desk shows a code. In the Mac and iPad apps, Microsoft's sign-in page opens in a sheet with the code
   already entered; in a browser it opens in a new tab with the code copied, so paste it.
3. Pick or type your `@sailpoint.com` account and finish SSO and MFA. The sheet starts with no saved
   sign-ins, so a personal Microsoft account signed in elsewhere isn't picked by mistake.
4. Accept reading and updating your calendar. SF Desk only adds the Deal Support and No DS Required
   categories to meetings (see [OUTLOOK.md](OUTLOOK.md)).

SF Desk then shows your main calendar. The sign-in is kept (`data/graph-token.json` on a computer, the
Keychain on the iPad) until you choose **Sign out of Microsoft 365** in the same list.

## Windows

SF Desk for Windows comes as `SF-Desk-windows.zip`, one download for Intel, AMD and ARM (Snapdragon) PCs: the
installer puts in the Node.js built for the PC. You need Windows 10 or 11 (64-bit), Microsoft Edge (built
in) and your SailPoint Microsoft 365 account for the calendar.

1. Right-click the zip > **Extract All...**, open the extracted folder and double-click **Install SF Desk**.
   If SmartScreen warns, click **More info > Run anyway**. It installs into `%LOCALAPPDATA%\Programs\SF Desk`
   (no admin rights) and adds SF Desk to the Start menu and the Desktop.
2. SF Desk starts. The first time it offers to download the Salesforce CLI (unless one is installed) and opens
   your browser to sign in to `sailpoint.my.salesforce.com`.
3. Click **Connect**, open **Time Entry** and sign in to Microsoft 365 (see
   [Your Microsoft 365 calendar](#your-microsoft-365-calendar)). The sign-in is kept in
   `%LOCALAPPDATA%\SF Desk\data\graph-token.json`.

Closing the window keeps SF Desk running; the SF Desk icon by the clock reopens it and has **Settings...**
(Display Mode: Light, Dark or System Auto), **Restart Server**, **Show Server Log**, **Show Data Folder** and
**Quit SF Desk**. The `.env` settings file and data are in `%LOCALAPPDATA%\SF Desk`; running **Install SF Desk**
from a newer zip updates the app and keeps them.

### Building the Windows download

Anywhere npm and nodejs.org are reachable (e.g. in the cloud), `scripts/build-windows-package.sh` writes
`dist/SF-Desk-windows.zip`, with Node.js for both x64 and arm64. Running from a Git checkout on Windows also works: `npm start`, with `sf` from
your PATH.

## Optional: the Outlook add-in

SF Desk can also put a **Create Deal Support** button on meetings in Outlook. It needs a one-time HTTPS
certificate and adding the add-in to Outlook. In the Mac app, choose **SF Desk > Set Up Outlook Add-in...**.
Otherwise, in Terminal, in the SF Desk folder (`~/SF-Desk` for the Terminal installer), run `sh scripts/outlook-cert.sh --trust`, restart SF Desk, then follow
[OUTLOOK.md](OUTLOOK.md) from step 2. Updates keep the certificate.

## Where your data lives

Paths are inside `~/Library/Application Support/SF Desk` for the Mac app, `~/SF-Desk` for the Terminal
installer, or your checkout for a manual one.

- `data/sf-desk.db` holds a local copy of the accounts and opportunities you've loaded, your hidden
  records, and which meetings you've logged or marked as not needing a Deal Support. Deleting the
  `data` folder resets all of that; it's rebuilt as you use the app.
- `data/graph-token.json` keeps your Microsoft 365 sign-in (a refresh token, readable only by you).
  **Sign out of Microsoft 365** in Time Entry deletes it.
- Your Salesforce token is only held in memory and never written to disk. Every edit goes straight to
  Salesforce when you click **Save** or **Add**.
- The server only listens on `localhost`, so nobody else on the network can reach it.

## Updating a manual install

```bash
cd ~/Documents/SF-Desk
git pull
```

Then stop SF Desk with Ctrl+C and run `npm start` again. If the pull changed `package-lock.json`,
redo step 3's dependency step first.

## Troubleshooting

### Time Entry shows only "Salesforce events"

1. **Signed in to Microsoft 365?** The list at the top says **Sign in to Microsoft 365...** until you are;
   see [Your Microsoft 365 calendar](#your-microsoft-365-calendar).
2. **Signed in as the wrong account?** Choose **Sign out of Microsoft 365** and sign in again with your
   `@sailpoint.com` account. In a browser, a private window keeps other Microsoft sign-ins out of the way.
3. **An error above the calendar?** "needs renewing" means Microsoft ended the sign-in (a password change,
   for example): sign in again. "needs an administrator to approve" means IT has to approve SF Desk's
   access to calendars first.

### macOS says the installer, `node` or `better_sqlite3.node` can't be opened

Files from a browser download are quarantined by macOS. Open the installer with **Open Anyway** as in
the Terminal installer's step 1; it then clears the quarantine on everything it installs. If a dialog still
names a file in `~/SF-Desk`, run `xattr -dr com.apple.quarantine ~/SF-Desk` in Terminal and start
SF Desk again.

### Connect fails, or a message mentions a redacted or missing token

Recent versions of the Salesforce CLI hide the access token in `sf org display` (it shows as
`[REDACTED]`). SF Desk handles this by asking `sf org auth show-access-token` instead, so:

- Update the CLI if it's old: `sf update`, or install the latest `.pkg` again.
- Check the CLI can hand out a token: `sf org auth show-access-token` should print one for your
  SailPoint org (add `--target-org <alias>` if you use an alias).
- If the CLI login has expired, sign in again with the `sf org login web` command in step 2.
- If you have several orgs in the CLI, set `SF_TARGET_ORG` in `.env` to the right one.

### `npm install` fails or hangs

Errors such as `ETIMEDOUT`, `ECONNRESET`, `UNABLE_TO_GET_ISSUER_CERT_LOCALLY` or a Cisco Umbrella block
page mean the npm registry is blocked. Don't fight it: use the `git archive` commands in step 3 to
take `node_modules` from GitHub instead. The same applies to the Salesforce CLI; install it from the
`.pkg`, not npm.

### "Salesforce CLI (sf) not found"

The app couldn't find `sf` on its PATH. Run `which sf` in Terminal and put that full path in `.env` as
`SF_CLI_PATH=`, then restart SF Desk.

### `Cannot find module 'better-sqlite3'` or another missing module

`node_modules` is missing or incomplete. Redo the dependency step in step 3 from the project folder.

### `EADDRINUSE` on port 3000

Another program (or a second copy of SF Desk) is using port 3000. Close it, or set `PORT=3001` in
`.env` and open http://localhost:3001 instead.

### Salesforce says the API isn't enabled for your user

Your Salesforce profile needs the **API Enabled** permission. Ask the Salesforce admins.

For what each tab does and the optional `.env` settings, see the [README](README.md).
