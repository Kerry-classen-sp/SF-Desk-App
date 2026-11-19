# SF Desk release notes

## 1.9.0 (November 18, 2026)

Everything from the 1.7.5 builds below, as one release:

- **Microsoft 365 is the calendar:** Time Entry reads your meetings from Microsoft 365 (or Salesforce events) on the
  Mac, Windows and the iPad, with SailPoint's SF Desk app registration built in. Sign-in opens in a sheet on the
  Mac and iPad apps, with a fresh session and the code entered for you. Calendars on the device itself are no
  longer read.
- **Deal Support tags in Outlook:** meetings with a Deal Support get the green Deal Support category and those
  needing none the gray No DS Required one, and a Deal Support covers only one occurrence of a recurring meeting.
- **New meeting from free time:** click an empty spot on the Time Entry calendar to create a meeting and its Deal
  Support together.
- **Remove this event:** on an event's right-click menu, with a confirmation saying what happens.
- **Security:** updated body-parser and qs.

### Build 3

- **Show declined:** meetings you declined in Microsoft 365 are hidden on Time Entry. Tick **Show declined** above
  the calendar (remembered on each device) to show them in yellow.
- **Edit an event:** right-click (or long-press) an event and choose **Edit** for a form with Outlook's options:
  title, required and optional attendees, start, end, all day, repeat, location, Teams meeting, show as, reminder,
  importance, categories, private, response options and description. For meetings someone else organized you can
  accept, tentatively accept or decline (with an optional message) and change show as, reminder, private and
  categories. Salesforce events get the fields Salesforce has. A Deal Support stays with its meeting when the
  meeting's time or title changes.

### Build 2

- **Long press on the iPad:** press and hold an event on Time Entry to open its menu (Create Deal Support, No Deal
  Support needed, Remove this event), as right-click does on the Mac and Windows.
- **Removing an event deletes its Deal Supports:** the confirmation lists them by number. The event goes first,
  so if that fails they're left alone. If your Salesforce user can't delete Deal Supports, the event isn't
  removed either.

## 1.7.5 (November 10, 2026)

- **TES and RFP Requests on the opportunity:** above its Deal Supports, an opportunity shows a **TES/RFP
  Requests** box with its open TES Requests and RFP Requests. **Show all** adds completed and cancelled ones,
  and **New TES Request** creates one. Click a TES Request to see it in a dialog, where its TES Stage can be
  changed. RFP Requests link to Salesforce.
- **Create TES Requests:** the form has TES Stage, TES Type, Tech Specialist Role and Preferred TES Start
  Date on the left, Products on the right and Notes across the bottom.
- **TES tab:** lists TES Requests on all open opportunities (no longer only the last 90 days), open ones by
  default; **Show all** adds completed and cancelled ones. Click a request to open the same dialog to see
  and update it, and **New TES Request** asks for the opportunity first.
- **Deal Support form:** Related TES Link and RFP Request only list open requests.
- **DS Time activities by opportunity:** the activity list is grouped by opportunity with a subtotal for
  each and a total at the bottom. Click a group to open it, or tick **Expand all**.
- **My time on opportunities:** the account's opportunity table has a **My time** column (your hours on its
  Deal Supports) in place of Next Step, with a narrower Probability column. An opened opportunity shows your
  time too.
- **Refresh:** a refresh button in the header reloads the current view. On iPad and iPhone, pull down.
- **Move My Time:** a message stays up while the move runs, so you don't switch away part way through.
- **Security:**
  - SF Desk only answers requests addressed to `localhost`, so a website can't reach it by pointing its own
    domain name at your computer.
  - The Outlook certificate's authority now only works for `localhost`, and its private key is deleted once
    it has signed SF Desk's certificate. **Set Up Outlook Add-in** replaces an older one (macOS asks for
    your password once).
  - [docs/SECURITY.md](SECURITY.md) explains how SF Desk signs in, what it stores and how it keeps data safe.
- **iPad and iPhone (preview):** an iOS version of SF Desk runs the same core on the device, with no
  server (see [docs/IOS.md](IOS.md)). It isn't distributed yet.

Build 2 (November 10, 2026):

- **Tabs on the opportunity:** under its details, an opportunity has a **Deal Supports** tab (where it
  opens) and a **TES/RFP Requests** tab, which shows how many requests are open.
- **New RFP Request:** the RFP Requests list has a button to create one, asking for what the submitter
  supplies: Date Due to Customer, Platform Request, Partner(s) and Executive Summary Needed (required), plus
  Signature Needed, Evaluator Guide Used, the SSJ, RFP document and portal checkboxes, positioning and notes.
- **The Deal Supports behind a request:** click a TES or RFP Request to see the Deal Supports linked to it
  (by Related TES Link or RFP Request), everyone's, with yours in bold and your total and everyone's.
- **My time on requests:** the TES and RFP Requests lists, on the opportunity and on the TES tab, show your
  hours on the Deal Supports linked to each request, and your total.
- **Exchange calendar only:** Time Entry reads only your Exchange calendar, on a Mac and on Windows. iCloud,
  Google and other calendars on the computer aren't listed or read.

Build 3 (November 10, 2026):

- **iPad and iPhone:** Time Entry reads only the Exchange calendar there too, and the app has the same
  version and build number as the desktop apps (`ios/build-device.sh` builds and installs it).

Build 4 (November 10, 2026):

- **iPad app on TestFlight:** the iOS app is now iPad only (it also runs on Apple silicon Macs) and is
  ready for TestFlight: `ios/testflight.sh` archives and uploads it, Release builds log less, and it has a
  privacy manifest. See [docs/IOS.md](IOS.md#testflight) and, for encryption,
  [docs/EXPORT-COMPLIANCE.md](EXPORT-COMPLIANCE.md).
- **Docs:** all the documentation is now in `docs/`.

Build 5 (November 12, 2026):

- **New Deal Supports are Complete:** the create form's Status starts as Complete (it can still be
  changed), and a Deal Support created without a Status, e.g. from the Outlook add-in, is saved as Complete.

Build 6 (November 16, 2026):

- **Notes and Next Steps (first version):** Notes and Next Steps tabs inside each Deal Support. Replaced in
  build 7 by tabs on the opportunity.

Build 7 (November 16, 2026):

- **Notes and Next Steps on the opportunity:** next to Deal Supports and TES/RFP Requests, an opportunity
  has a **Notes** tab and a **Next Steps** tab (each loads when first opened). Notes lists its Salesforce
  notes; click one, or **New Note**, to edit its Title and Text, with Save, Cancel and Delete. Next Steps
  lists every update to the opportunity's Most Recent NEXT STEP (its history in Salesforce), newest first,
  with who entered it; **New Next Step** sets it, for users Salesforce lets change that field.
- **Deal Supports:** the Notes and Next Steps tabs inside each Deal Support are gone.

Build 8 (November 17, 2026):

- **Security:** body-parser 1.20.9 (GHSA-27r3-jxmh-p828, high) and qs 6.16.2 (moderate), the two
  vulnerable packages Express pulls in. Express stays on 4 and dotenv on 16.

Build 10 (November 18, 2026):

- **SF Desk's own Microsoft 365 app:** new installs sign in to Microsoft 365 through SailPoint's SF Desk
  app registration instead of Microsoft's shared Graph Command Line Tools client. On the Mac too, the
  calendar can come from Microsoft 365, and meetings with a Deal Support get the Deal Support category in
  Outlook. Existing installs get this by adding the same settings to their `.env`.

Build 11 (November 18, 2026):

- **Pick the Microsoft 365 account:** on the Mac, Microsoft's sign-in page opens in its own SF Desk window
  with a fresh session instead of in the browser, so Microsoft asks which account to use rather than
  signing in with the browser's. The code is copied, ready to paste.

Build 12 (November 18, 2026):

- **Microsoft 365 sign-in in the SF Desk window:** on the Mac, Microsoft's sign-in page opens as a sheet on
  the SF Desk window (still with a fresh session), and closes by itself once you're signed in. **Close**
  (or Esc) closes it sooner.

Build 13 (November 18, 2026):

- **No code to enter:** on the Mac, the sign-in sheet enters Microsoft's code itself and starts at
  Microsoft's own sign-in (your email, password and MFA).

Build 14 (November 18, 2026):

- **No DS Required in Outlook from SF Desk:** with Microsoft 365 marking on, meetings marked as needing no Deal
  Support get the gray **No DS Required** category in Outlook, as the add-in does, and meetings with a Deal
  Support keep getting the green Deal Support one. Changing a meeting swaps its category, and undoing takes it
  off. SF Desk asks Outlook to create both categories with their colors; where your tenant doesn't allow that,
  they're added without a color unless the add-in has created them already.

Build 15 (November 18, 2026):

- **One Deal Support, one occurrence:** a Deal Support covers a single occurrence of a recurring meeting, in
  Outlook too. When SF Desk tags a week, a Deal Support category on a recurring series (which shows on every
  occurrence) comes off the series and goes only on the occurrence a Deal Support covers, and meetings without
  one lose a stray Deal Support category. No DS Required put on a whole series is left alone.

Build 16 (November 18, 2026):

- **Microsoft 365 is the calendar:** Time Entry reads meetings from Microsoft 365 (through Microsoft Graph)
  or Salesforce events, and nothing else. SF Desk no longer reads the Mac's Calendar, classic Outlook on
  Windows or the iPad's calendars, so it doesn't ask for calendar access and the Mac app has no calendar
  reader inside. If you used one of those, pick **Sign in to Microsoft 365...** in Time Entry's list. Meetings
  still show as covered when one of your Deal Supports matches them (same date and opportunity, account or
  title). Marks made on the Mac's Calendar carry over where SF Desk had already matched them to the meeting;
  others may need making again.
- **iPad:** Microsoft 365 works on the iPad too, with the same sign-in sheet as the Mac (a fresh session, the
  code entered for you) and the same tagging in Outlook. The sign-in is kept in the Keychain.
- **Installers:** the Mac Terminal installer no longer asks for the Xcode Command Line Tools or Internet
  Accounts, and the Windows installer no longer looks for classic Outlook.

Build 17 (November 18, 2026):

- **New meeting from free time:** click an empty spot on the Time Entry calendar to create a meeting and its
  Deal Support together. The dialog starts with the meeting's title, date and times (on the half hour clicked,
  for an hour) above the usual Deal Support form, whose date and hours follow the meeting's. The meeting is
  added to the calendar shown: in Microsoft 365 with no attendees, so no invitations are sent, or as a
  Salesforce event on the opportunity. It then shows on the calendar as covered by its Deal Support.

Build 18 (November 18, 2026):

- **Remove this event:** right-click an event on Time Entry to remove it from its calendar. SF Desk first says
  what that does: a Microsoft 365 meeting you organized is cancelled for its attendees, one you were invited to
  just leaves your calendar, only the occurrence clicked of a recurring meeting goes, and a Salesforce event
  goes to the Recycle Bin. Deal Supports for it stay in Salesforce.

Build 19 (November 18, 2026):

- **iPad: Microsoft 365 sign-in opens:** choosing **Sign in to Microsoft 365...** on the iPad now opens
  Microsoft's sign-in sheet; before, iOS blocked it, so only the code showed. The link in the code box opens the
  same sheet, with the code entered, everywhere.

## 1.7.1 (October 30, 2026)

- **Starts even with a damaged Outlook certificate:** an unreadable certificate in SF Desk's `certs` folder
  ("PEM routines::no start line") stopped SF Desk from starting. Now only the Outlook add-in is off until
  **SF Desk > Set Up Outlook Add-in** makes a new certificate, which it now does whenever the old one can't
  be read. New certificates are written only once complete, so an interrupted setup leaves nothing broken.

Build 2 (October 30, 2026), Outlook add-in:

- **No DS Required:** the create form's Cancel button marks the meeting as needing no Deal Support (and
  **Needs a Deal Support after all** undoes it).
- **Green and gray:** a meeting with a Deal Support gets the green "Deal Support" category, one marked No DS
  Required the gray "No DS Required" category, and any other meeting loses both. Recurring meetings get
  neither, since Outlook would put it on every occurrence.
- **Same view as Time Entry:** marks and Deal Supports created from a meeting are saved under a key from its
  start and subject, so the add-in and Time Entry agree whichever calendar they read. The add-in matches
  against the whole day's meetings, so each meeting has one Deal Support or none and no Deal Support is on
  two meetings, and each occurrence of a recurring meeting is its own.

Build 3 (November 7, 2026):

- **Pipeline, Wins or Losses:** on the Deals tab, the heading is a dropdown. Wins (100-Won) and Losses
  (999-Lost) cover deals closed since the start of last fiscal year, with their own tiles, a chart by
  opportunity type, and the close-date chart running back through last fiscal year.
- **Deal Support picklists offer only valid values:** each picklist lists the values of your default
  record type, and a dependent picklist (like Role) only those allowed for its controlling field, so saving
  no longer fails with "bad value for restricted picklist".
- **Fewer opportunities to wade through:** the Deal Support opportunity picker and the Accounts page's
  opportunity lists leave out contract renewals ("CON-" and "Renewal" in the name) and Professional
  Services price book opportunities. **Show all** (formerly Show closed) adds them back, with closed ones.
- **Errors can be read:** a Deal Support form's errors show in the form and above it, not behind it.
- **Phones:** in a narrow window, Time Entry shows one day at a time.

## 1.7.0 (October 28, 2026)

- **Deals follow the forecast period:** the Closing table and the Pipeline by stage chart show the month,
  fiscal quarter or fiscal year picked on the Forecast chart, and ‹ › step one period at a time. Axis labels
  read like "Oct '26".
- **Sort any table:** click a column heading to sort by it, again to reverse. Subtotal rows stay with their
  group.
- **My Time, Month:** "30 days" is now Month, the whole calendar month.
- **Opportunity Deal Supports:** the table shows Customer Facing Time and Total Time with their totals, and
  no longer the Created date.
- **Account Deal Supports:** Customer Facing Time and Total Time, with a subtotal for each opportunity and a
  total (also in the Excel export). Opportunities on the Accounts page are listed newest first.
- **One Deal Support per meeting:** on Time Entry (and in the Outlook add-in), a Deal Support covers only the
  meeting it was created from, or else the one meeting that matches it best that day. A meeting title must
  name the account (e.g. "Koch"), not just share a word with it.

## 1.6.0 (October 26, 2026)

- **My Team periods:** the buttons are Year, Quarter, Month, Week and Custom, with ‹ and › to step back and
  forward a period at a time (fiscal years and quarters). Clicking a period goes back to the current one, and
  My Team opens on Quarter.
- **Renewals left out:** Deals and My Team's sales leave out opportunities of type Renewal ("Renewal with
  Upsell" still counts).
- **Move My Time from open opportunities:** move your Deal Supports from any opportunity, open or closed, to
  another open one on the same account.
- **Marking meetings in Outlook (off for now):** SF Desk can add the Deal Support category to every covered
  meeting through Microsoft 365, once IT approves calendar updates and `SF_DESK_OUTLOOK_MARK=1` is set (see
  OUTLOOK.md).

## 1.5.1 (October 22, 2026)

- **My Team, Show All:** tick it to rank everyone in the records you can see instead of only your team.
- **My Team, BOAT:** the Everyone table shows each person's SailPoint BOAT, the one with most of the accounts
  they're Account Lead SE on (hover for the others).
- **My Team, sorting and export:** click any column in the Everyone table to sort by it (again to reverse),
  and **Export to Excel** saves the table as shown, with BOAT and Other BOATs columns.

## 1.5.0 (October 22, 2026)

- **My Team tab:** ranks you and your team (your Salesforce default team, else the people who share your
  manager) for This year, This quarter, This month, This week or a custom date range. Rank by Deal Support
  Internal, Customer Facing, Travel or Total time (by Assigned SE and Date of Activity), or by Sales in ACV or
  TCV (opportunities won in the period where each is the Lead SE). Each category has a tile with the team
  total and the leader; click a tile or a column to rank by it. Year and quarter are fiscal.

## 1.4.0 (October 22, 2026)

- **New Deal Support opens in a dialog:** the opportunity, then Date of Activity, Requested Activity, Role,
  and Platform Request, Platform Capabilities and Integration Modules as checkbox lists side by side. Then
  the description, and Customer Facing, Internal and Travel Time with their total. The account comes from the
  opportunity.
- **Description written for you:** it's proposed from the activity, platform request, capabilities and
  modules as you pick them, until you type in it. **Write it** puts the proposal back.
- **Role and activity filled in:** Role is Lead SE when you're the opportunity's Lead SE (or, when it has
  none, the account's), else SME, until you pick one. Requested Activity is Demo when the meeting mentions a
  demo, else Discussion.
- **Show Closed Opportunities:** tick it beside the opportunity search to find closed opportunities too.
  They're searched in Salesforce as you type, listed after the open ones, and marked closed.
- **RFP and TES requests:** pick the RFP Request and Related TES Link from the requests on the chosen
  opportunity and its account, instead of typing an Id.
- **Time Entry:** right-click a meeting to Create Deal Support or mark it No Deal Support needed.
- **Deals:** Show as ACV or Show as TCV totals SaaS Total ACV or SaaS TCV throughout.
- **Accounts:** the opportunities table is read-only, and Open takes you to the opportunity in Salesforce.

## 1.3.0 (October 15, 2026)

- **TES tab:** the TES Requests where you (My Accounts), your team or one team member is the Opportunity Lead
  SE or Assigned SE, grouped by TES Stage (Requested, Planning, Active, Stalled, Completed, Cancelled) and then
  by customer. Most Recent TES Status shows in green, yellow or red; Stalled is in red; a Last Update Date
  over 10 days old turns yellow, and over 15 days red. Click a request for its TES Status updates (who
  entered each) and to add one. Completed and Cancelled requests show for the last 90 days, with Show more
  reaching back a year. Over 100 requests, the stages start collapsed, and a stage over 50 shows them a page
  at a time. **Add TES Request** opens Salesforce's New Deal Support: TES Request.
- **Opportunity view:** read-only (change opportunities in Salesforce), with the account and sales rep in
  larger type. Click the account for a pop-up of its details, opportunities and Deal Supports. From the TES
  tab, the opportunity opens in a pop-up too.
- **Settings:** SF Desk > Settings... (the tray icon's Settings... on Windows) sets Display Mode to Light,
  Dark or System Auto. It replaces Edit Settings; `.env` is in the data folder (Help > Show Data Folder).
- **Starts connected:** SF Desk connects to Salesforce on opening, with no Connect click. If your
  Salesforce CLI login is missing or expired, **Sign in to Salesforce** opens the Salesforce login in your
  browser and connects once you're done.
- **Faster start on Windows:** the window opens without waiting for the Salesforce login check, and the
  apps open as soon as their server is ready.
- **One Windows download** (`SF-Desk-windows.zip`) for Intel, AMD and ARM PCs: the installer picks the
  Node.js for the PC.
- **Accounts:** the list's count is in the heading, and it pages at 100. Each launch opens on My BOAT(s),
  My Accounts and All sales reps.
- **Deals:** the Forecast by close date chart starts at the current month, quarter or year, with wider bars.
- Text boxes and dropdowns line up at one height.

## 1.2.1 (October 14, 2026)

- The server code now lives in a `src` folder. Nothing changes in how SF Desk looks or works.
- Help links in the app, the disk image and the Outlook add-in point to the SF-Desk-App repository.

## 1.2.0 (October 14, 2026)

- **Filters everywhere:** Accounts, Deals and DS Time can all be narrowed by SailPoint BOAT, team and sales
  rep. Picking a BOAT narrows the SE and sales rep lists to people with accounts in it. On Accounts the
  filters now sit in a bar across the top, like Deals and DS Time.
- **Starts where you work:** each launch opens on My BOAT(s), My Accounts and All sales reps. If your BOAT
  can't be found, it starts on All BOATs.
- **DS Time** (renamed from My Time): counts your hours from every Deal Support field that names you, with
  no Mine by or Date choices to set. Filter by you, your team or one team member, and it keeps the team and
  sales rep you picked on the other tabs.
- **Bulk changes on Accounts:** tick one account or all of them, then Hide or Unhide, or Change SE or Change
  Rep, in one go.
- **Deal Supports from meetings:** the name and notes come from the meeting's Salesforce copy, and internal
  meetings go to Internal Time.
- Connect shows its progress while it signs you in.

## 1.1.0 (October 14, 2026)

- **SF Desk.app for Mac:** a self-contained app with its own window, installed from a disk image. It brings
  its own Node.js, reads your Mac calendar, and sets up the Outlook add-in from the SF Desk menu.
- **SF Desk for Windows:** the same app for Windows 10 and 11 (Intel/AMD and ARM), reading your Outlook or
  Microsoft 365 calendar.
- **Accounts:** a My Accounts filter, the SailPoint BOAT in the account details, and Change Rep and Change SE
  buttons that confirm with a short summary.
- The Dashboard tab is now called **Deals**.
- **Time Entry:** export the week's Deal Supports to Excel.

## 1.0.0

- Accounts and opportunities where you're the Lead SE, with editing, hiding and a local copy that keeps
  working when Salesforce can't be reached.
- Sign-in with your Salesforce CLI login.
- Deal Supports on each opportunity, created and edited from SF Desk.
- Deals: your open pipeline by stage with a fiscal-year forecast, and Excel export.
- My Time: your hours from Deal Supports by week, period and opportunity.
- Time Entry: your week's meetings, green when they have a Deal Support, with one-click creation from a
  meeting.
- The Outlook add-in: create a Deal Support from a meeting in Outlook.
