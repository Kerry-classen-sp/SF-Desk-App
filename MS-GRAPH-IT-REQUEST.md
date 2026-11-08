**Subject: Request to approve Microsoft Graph calendar permissions for SF Desk**

**What SF Desk is**

SF Desk is an internal tool used by the Solutions Engineering team. It runs locally on each user's Mac or
Windows PC and helps us log customer meetings as Deal Support records in Salesforce. It reads the user's own
Microsoft 365 calendar to list their meetings. With this approval it will also mark each meeting with an
Outlook category: green "Deal Support" when the meeting has a Deal Support record, and gray "No DS Required"
when it doesn't need one.

**What we're asking for**

Admin consent for these **delegated** Microsoft Graph permissions:

| Permission | Type | Why |
|---|---|---|
| `User.Read` | Delegated | Read the signed-in user's name and email address, to show which account is connected. |
| `Calendars.ReadWrite` | Delegated | Read the user's own calendar events, and add or remove SF Desk's two categories on them. |
| `offline_access` | Delegated | Stay signed in between sessions (refresh token), so users don't have to sign in every day. |

`Calendars.Read` alone is enough for reading. `Calendars.ReadWrite` is needed only to set the categories.

**Scope and limits**

- **Delegated only:** no application permissions. SF Desk acts only as the signed-in user, and only on that
  user's own mailbox. It can't reach other users' calendars or anything outside the calendar.
- **The only write:** SF Desk changes nothing on a meeting except its `categories` field. It never creates,
  deletes, reschedules or edits meetings, attendees, bodies or responses, and it sends no mail.
- **Graph calls it makes:**
  - `GET /me` for the user's name and email.
  - `GET /me/calendars` to list the user's calendars.
  - `GET /me/calendars/{id}/calendarView` and `GET /me/calendarView` to read meetings in a date range.
  - `PATCH /me/events/{id}`, with a body that contains only `categories`.
- **Data stays on the user's computer:** meeting details are read by SF Desk on the user's own computer. They
  aren't sent to any third-party service. The only thing that leaves the computer is the Deal Support record
  the user chooses to create in our Salesforce org, through the user's own Salesforce login.
- **The sign-in:** the refresh token is stored in the user's SF Desk data folder (`graph-token.json`, readable
  only by that user). Signing out in SF Desk deletes it. Revoking the user's sessions in Entra ID also ends it.

**How sign-in works**

SF Desk uses Microsoft's device code flow. It shows a code, the user enters it at `microsoft.com/devicelogin`,
and the user signs in with their normal company account, including MFA and Conditional Access. There's no
client secret, and no password ever goes through SF Desk.

**Which app to approve: two options**

1. **Approve Microsoft's own public client.** By default, SF Desk signs in as **"Microsoft Graph Command Line
   Tools"**, application ID `14d82eec-204b-4c2f-b7e8-296a70dab67e`. This is Microsoft's own app, so nothing
   needs registering. Approving `Calendars.ReadWrite` for it also grants that permission to anyone using
   Microsoft Graph PowerShell or CLI tools with that app. IT may prefer option 2 for that reason.
2. **Register a dedicated app (recommended if you want tighter control).** Create an Entra ID app
   registration, for example "SF Desk":
   - Supported account types: this organization only (single tenant).
   - Authentication: **Allow public client flows = Yes** (needed for device code). No redirect URI or client
     secret is needed.
   - API permissions: Microsoft Graph, delegated: `User.Read`, `Calendars.ReadWrite`, `offline_access`. Then
     grant admin consent.
   - Optionally, require user assignment and assign it to the SE team only.

   Please send us the **Application (client) ID** and **Directory (tenant) ID**. SF Desk is configured to use
   them with two settings, `SF_DESK_GRAPH_CLIENT_ID` and `SF_DESK_GRAPH_TENANT`.

**Who it's for**

Members of the Solutions Engineering team who use SF Desk. Consent can be limited to that group if you register
a dedicated app and require user assignment.
