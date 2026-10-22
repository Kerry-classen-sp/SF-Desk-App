# SF Desk release notes

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
