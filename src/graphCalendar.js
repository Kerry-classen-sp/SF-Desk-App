// Reads your Microsoft 365 calendars through Microsoft Graph, the calendar SF Desk uses besides Salesforce's.
// Sign-in uses the device code flow with a public client (SailPoint's SF Desk app registration, or Microsoft's own
// "Microsoft Graph Command Line Tools" when none is set): SF Desk gets a code, Microsoft's page takes it (the Mac
// and iPad apps enter it themselves), and the host keeps the refresh token (the data folder's graph-token.json on
// the desktop, the Keychain on the iPad). Your organization may require an admin to approve the client for
// Calendars.ReadWrite; Microsoft's error then says so and the page shows it.
// The writes are tagging meetings (markCategory: the Deal Support category on meetings that have one, and No DS
// Required on meetings marked as needing none), adding a meeting you create with a Deal Support (createEvent),
// changing or answering one from the edit form (updateEvent, respondEvent) and removing one you choose to
// (deleteEvent).
// Sign-ins from before that only granted Calendars.Read; they keep reading until signed in again.
// Plain JavaScript with no Node modules, as it also runs in JavaScriptCore on the iPad (see ios/build-core.sh).

import { sha1Hex } from './sha1.js';

const GRAPH = 'https://graph.microsoft.com/v1.0';
const DEFAULT_CLIENT_ID = '14d82eec-204b-4c2f-b7e8-296a70dab67e';
const READ_SCOPE = 'offline_access User.Read Calendars.Read';
const WRITE_SCOPE = 'offline_access User.Read Calendars.ReadWrite';
const canWrite = (scope) => /(^|\s|\/)Calendars\.ReadWrite(\s|$)/i.test(String(scope || ''));
// URLSearchParams, which JavaScriptCore doesn't have.
const formBody = (params) => Object.entries(params).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');

class CalendarError extends Error {
  constructor(message, status = 502) { super(message); this.status = status; }
}

// opts: { clientId, tenant, markEnabled (Calendars.ReadWrite, for tagging meetings; off until the tenant approves it,
// as asking for it would block plain reading until then), fetch, sleep(ms) -> Promise, load() -> saved sign-in or
// null, save(saved or null) }.
export function graphCalendar(opts) {
  const { fetch, sleep } = opts;
  const CLIENT_ID = opts.clientId || DEFAULT_CLIENT_ID;
  const LOGIN = `https://login.microsoftonline.com/${opts.tenant || 'organizations'}/oauth2/v2.0`;
  const MARK_ENABLED = !!opts.markEnabled;
  const SCOPE = MARK_ENABLED ? WRITE_SCOPE : READ_SCOPE;
  const appName = opts.clientId ? 'SF Desk' : 'Microsoft Graph Command Line Tools';

  // Microsoft's errors, in words. AADSTS65001/90094/90099 and friends mean the tenant wants an admin to
  // approve the client first.
  function explain(data, fallback) {
    const desc = String(data?.error_description || data?.error?.message || fallback || '').split('\r\n')[0];
    if (/AADSTS(65001|90094|90099|900941|50105|53003)/.test(desc) || /admin(istrator)? (approval|consent)/i.test(desc)) {
      return `Your organization needs an administrator to approve "${appName}" ${MARK_ENABLED ? 'reading and updating' : 'reading'} ` +
        `your calendar (${MARK_ENABLED ? 'Calendars.ReadWrite' : 'Calendars.Read'}) before SF Desk can use Microsoft 365. Ask IT, or use Salesforce events. (${desc})`;
    }
    return desc || 'Microsoft 365 sign-in failed.';
  }

  async function form(url, params) {
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: formBody(params) });
    return { ok: r.ok, data: await r.json().catch(() => ({})) };
  }

  let saved = null; // { refresh_token, scope, account }
  try { saved = opts.load() || null; } catch { /* not signed in */ }
  let access = null; // { token, expires }
  let pending = null; // the device code sign-in in progress
  let lastError = '';
  const names = new Map(); // calendar id -> name, from calendars()

  const save = () => {
    try { opts.save(saved); } catch (err) { console.warn(`Couldn't save the Microsoft 365 sign-in: ${err.message}`); }
  };

  async function useTokens(data) {
    access = { token: data.access_token, expires: Date.now() + (Number(data.expires_in) || 3600) * 1000 - 60_000 };
    saved = { ...saved, refresh_token: data.refresh_token || saved?.refresh_token, scope: data.scope || saved?.scope || '' };
    if (!saved.account) {
      const me = await graph('/me?$select=displayName,mail,userPrincipalName');
      saved.account = me.mail || me.userPrincipalName || me.displayName || '';
    }
    save();
  }

  async function token() {
    if (access && access.expires > Date.now()) return access.token;
    if (!saved?.refresh_token) throw new CalendarError('Sign in to Microsoft 365 first.', 400);
    const { ok, data } = await form(`${LOGIN}/token`, { client_id: CLIENT_ID, grant_type: 'refresh_token', refresh_token: saved.refresh_token,
      scope: canWrite(saved.scope) ? SCOPE : READ_SCOPE });
    if (!ok) {
      // A refused refresh (expired, revoked, password changed) needs a new sign-in; a network error doesn't.
      if (data?.error) { saved = null; access = null; save(); }
      throw new CalendarError(`Microsoft 365 sign-in needs renewing: ${explain(data, 'no answer')}`, 400);
    }
    await useTokens(data);
    return access.token;
  }

  async function graph(pathAndQuery, headers = {}, { method = 'GET', body } = {}) {
    const url = pathAndQuery.startsWith('https://') ? pathAndQuery : GRAPH + pathAndQuery;
    const r = await fetch(url, { method, headers: { Authorization: `Bearer ${await token()}`, ...(body ? { 'Content-Type': 'application/json' } : {}), ...headers },
      ...(body ? { body: JSON.stringify(body) } : {}) });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new CalendarError(`Microsoft 365: ${explain(data, r.statusText)}`, r.status === 403 ? 403 : 502);
    return data;
  }

  // Start a device code sign-in; the code and link are for the page to show. Polls in the background.
  async function startSignIn() {
    if (pending && pending.expires > Date.now()) return pending.info;
    lastError = '';
    const { ok, data } = await form(`${LOGIN}/devicecode`, { client_id: CLIENT_ID, scope: SCOPE });
    if (!ok) throw new CalendarError(explain(data, 'Microsoft didn\'t start the sign-in.'), 400);
    const info = { userCode: data.user_code, verificationUri: data.verification_uri, message: data.message, expiresIn: data.expires_in };
    const me = pending = { info, expires: Date.now() + data.expires_in * 1000 };
    (async () => {
      let wait = (Number(data.interval) || 5) * 1000;
      while (pending === me && Date.now() < me.expires) {
        await sleep(wait);
        if (pending !== me) return;
        const res = await form(`${LOGIN}/token`, { client_id: CLIENT_ID, grant_type: 'urn:ietf:params:oauth:grant-type:device_code', device_code: data.device_code })
          .catch((err) => ({ ok: false, data: { error: 'network', error_description: err.message } }));
        if (res.ok) {
          saved = null;
          try { await useTokens(res.data); } catch (err) { lastError = err.message; }
          pending = null;
          return;
        }
        const code = res.data?.error;
        if (code === 'authorization_pending' || code === 'network') continue;
        if (code === 'slow_down') { wait += 5000; continue; }
        lastError = code === 'expired_token' ? 'The sign-in code expired. Try again.'
          : code === 'authorization_declined' ? 'The sign-in was cancelled.' : explain(res.data);
        pending = null;
        return;
      }
      if (pending === me) { pending = null; lastError = 'The sign-in code expired. Try again.'; }
    })();
    return info;
  }

  function status() {
    return { signedIn: !!saved?.refresh_token, canWrite: !!saved?.refresh_token && canWrite(saved.scope),
      account: saved?.account || '', pending: pending ? pending.info : null, error: lastError };
  }

  function signOut() {
    saved = null; access = null; pending = null; lastError = '';
    save();
  }

  // [{ id, title, account, type }]: ids are "graph:" + Graph's calendar id.
  async function calendars() {
    const data = await graph('/me/calendars?$select=id,name,owner,isDefaultCalendar&$top=100');
    for (const c of data.value || []) names.set('graph:' + c.id, c.name);
    return (data.value || []).map((c) => ({
      id: 'graph:' + c.id, title: c.name, account: `${c.owner?.address || saved?.account || 'Microsoft 365'} (Microsoft 365)`,
      type: 'exchange', isDefault: !!c.isDefaultCalendar, source: 'graph',
    })).sort((a, b) => b.isDefault - a.isDefault || a.title.localeCompare(b.title));
  }

  const localDay = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

  // Events between two instants in the given calendars, each with a stable id for its occurrence.
  async function events(fromIso, toIso, ids) {
    const me = String(saved?.account || '').toLowerCase();
    const select = 'id,iCalUId,subject,start,end,isAllDay,location,body,organizer,attendees,isCancelled,showAs,isOrganizer,type,responseStatus,onlineMeeting';
    const out = [];
    for (const id of ids) {
      const calId = id.replace(/^graph:/, '');
      let url = `/me/calendars/${encodeURIComponent(calId)}/calendarView?` +
        formBody({ startDateTime: fromIso, endDateTime: toIso, $select: select, $top: '200', $orderby: 'start/dateTime' });
      const title = names.get(id) || 'Microsoft 365';
      while (url) {
        // Times in UTC, body as plain text (the description prefill strips invites from text).
        const page = await graph(url, { Prefer: 'outlook.timezone="UTC", outlook.body-content-type="text"' });
        for (const e of page.value || []) {
          // All-day events have no time zone: their dates are the calendar's own, so keep them as local midnights.
          const start = e.isAllDay ? new Date(e.start.dateTime.slice(0, 10) + 'T00:00:00') : new Date(e.start.dateTime + 'Z');
          const end = e.isAllDay ? new Date(e.end.dateTime.slice(0, 10) + 'T00:00:00') : new Date(e.end.dateTime + 'Z');
          out.push({
            uid: e.iCalUId || e.id, title: e.subject || '', start: start.toISOString(), end: end.toISOString(),
            date: localDay(start), allDay: !!e.isAllDay, location: e.location?.displayName || '',
            notes: String(e.body?.content || '').slice(0, 20000), calendar: title, calendarId: id,
            organizer: e.organizer?.emailAddress?.name || '', joinUrl: e.onlineMeeting?.joinUrl || '',
            attendees: (e.attendees || []).filter((a) => a.type !== 'resource').map((a) => ({
              name: a.emailAddress?.name || '', email: a.emailAddress?.address || '',
              me: !!me && String(a.emailAddress?.address || '').toLowerCase() === me,
            })),
            canceled: !!e.isCancelled, free: e.showAs === 'free',
            graphId: e.id, isOrganizer: e.isOrganizer !== false, recurring: e.type === 'occurrence' || e.type === 'exception',
            declined: e.isOrganizer === false && e.responseStatus?.response === 'declined',
          });
        }
        url = page['@odata.nextLink'] || '';
      }
    }
    return out.filter((e) => !e.canceled).map((e) => ({
      ...e,
      id: 'gr_' + sha1Hex(`${e.uid}|${e.start}`).slice(0, 24),
    }));
  }

  // A meeting in one of my calendars, from Graph's event fields (subject, start, end and so on; attendees, if any,
  // get invitations, with `signature` at the end of the description). Returns its id as events() gives it.
  async function createEvent(calendarId, fields, { signature = '' } = {}) {
    needWrite('add meetings to it');
    const calId = String(calendarId).replace(/^graph:/, '');
    const body = { ...fields };
    if (body.isOnlineMeeting) body.onlineMeetingProvider = 'teamsForBusiness';
    if (signature && body.attendees?.length) body.body = { contentType: 'text', content: withSignature(body.body?.content, signature) };
    const e = await graph(`/me/calendars/${encodeURIComponent(calId)}/events`, { Prefer: 'outlook.timezone="UTC"' }, { method: 'POST', body });
    return { id: occurrenceId(e, e.id) };
  }

  // The id events() gives a meeting, from Graph's (UTC) start and iCalUId.
  const occurrenceId = (e, graphId) => {
    const start = e.isAllDay ? new Date(e.start.dateTime.slice(0, 10) + 'T00:00:00') : new Date(e.start.dateTime + 'Z');
    return 'gr_' + sha1Hex(`${e.iCalUId || graphId}|${start.toISOString()}`).slice(0, 24);
  };
  const needWrite = (what) => {
    if (!canWrite(saved?.scope)) {
      throw new CalendarError(`Sign out of Microsoft 365 and sign in again, accepting updates to your calendar, to ${what}.`, 403);
    }
  };
  // graphId's meeting with the fields in `select`, after checking that it's the meeting SF Desk knows as `id`.
  async function checked(id, graphId, select, headers = {}) {
    const path = `/me/events/${encodeURIComponent(String(graphId || ''))}`;
    const e = await graph(`${path}?$select=iCalUId,start,isAllDay${select ? ',' + select : ''}`, { Prefer: 'outlook.timezone="UTC"', ...headers });
    if (occurrenceId(e, graphId) !== id) throw new CalendarError('That meeting changed in Outlook. Reload and try again.', 409);
    return { path, e };
  }

  // Removes one meeting (one occurrence of a series) from my calendar. For a meeting I organized, Microsoft sends
  // the attendees a cancellation, with `signature` as its message.
  async function deleteEvent(id, graphId, { signature = '' } = {}) {
    needWrite('remove meetings');
    const { path, e } = await checked(id, graphId, 'isOrganizer,attendees');
    const invited = e.isOrganizer !== false && (e.attendees || []).some((a) => a.type !== 'resource');
    if (signature && invited) await graph(`${path}/cancel`, {}, { method: 'POST', body: { comment: signature } });
    else await graph(path, {}, { method: 'DELETE' });
  }

  // The signature goes at the end of what's sent, once: text that already ends with it (or has it) is left alone.
  const flat = (s) => String(s || '').replace(/\s+/g, ' ').trim().toLowerCase();
  const htmlText = (h) => String(h || '').replace(/<(style|script)[\s\S]*?<\/\1>/gi, ' ').replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
  const hasSignature = (text, signature) => flat(text).includes(flat(signature));
  const withSignature = (text, signature) => {
    const t = String(text || '').replace(/\s+$/, '');
    return !signature || hasSignature(t, signature) ? t : t ? `${t}\n\n${signature}` : signature;
  };
  const htmlEscape = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const withSignatureHtml = (html, signature) => {
    if (!signature || hasSignature(htmlText(html), signature)) return null;
    const sig = `<div><br>${htmlEscape(signature).replace(/\r?\n/g, '<br>')}</div>`;
    const h = String(html || '');
    return /<\/body>/i.test(h) ? h.replace(/<\/body>(?![\s\S]*<\/body>)/i, `${sig}</body>`) : h + sig;
  };

  const DETAIL = 'subject,body,end,location,attendees,showAs,isReminderOn,reminderMinutesBeforeStart,sensitivity,importance,' +
    'categories,isOnlineMeeting,onlineMeeting,organizer,isOrganizer,responseStatus,responseRequested,allowNewTimeProposals,type,recurrence,webLink';
  // What the edit form shows of a meeting, as Outlook has it: times as UTC instants (all-day ones as dates, the end
  // date exclusive), the body as plain text, rooms apart from people.
  async function eventDetails(id, graphId) {
    const { e } = await checked(id, graphId, DETAIL, { Prefer: 'outlook.timezone="UTC", outlook.body-content-type="text"' });
    const person = (a) => ({ name: a.emailAddress?.name || '', email: a.emailAddress?.address || '' });
    return {
      kind: 'graph', subject: e.subject || '', body: String(e.body?.content || ''), allDay: !!e.isAllDay,
      start: e.isAllDay ? e.start.dateTime.slice(0, 10) : new Date(e.start.dateTime + 'Z').toISOString(),
      end: e.isAllDay ? e.end.dateTime.slice(0, 10) : new Date(e.end.dateTime + 'Z').toISOString(),
      location: e.location?.displayName || '',
      attendees: (e.attendees || []).filter((a) => a.type !== 'resource').map((a) => ({ ...person(a), type: a.type, response: a.status?.response || 'none' })),
      rooms: (e.attendees || []).filter((a) => a.type === 'resource').map(person),
      showAs: e.showAs || 'busy', reminder: e.isReminderOn ? Number(e.reminderMinutesBeforeStart) || 0 : null,
      private: e.sensitivity === 'private', importance: e.importance || 'normal', categories: e.categories || [],
      teams: !!e.isOnlineMeeting, joinUrl: e.onlineMeeting?.joinUrl || '', organizer: person(e.organizer || {}),
      isOrganizer: e.isOrganizer !== false, response: e.responseStatus?.response || 'none',
      responseRequested: e.responseRequested !== false, allowNewTimeProposals: e.allowNewTimeProposals !== false,
      type: e.type || 'singleInstance', recurrence: e.recurrence || null, webLink: e.webLink || '',
    };
  }

  // Saves the changed fields of a meeting (Graph's own names: subject, body as text, start/end, isAllDay, location,
  // attendees, showAs, reminder, sensitivity, importance, categories, isOnlineMeeting, responseRequested,
  // allowNewTimeProposals, recurrence). Rooms stay when the attendees change. For a meeting I organized with
  // attendees, Microsoft sends them the update, with `signature` at the end of the description (added to the
  // description as it is, formatting kept, when it isn't being changed). Returns the meeting's id as events() will give it.
  async function updateEvent(id, graphId, changes, { signature = '' } = {}) {
    needWrite('change meetings');
    const { path, e } = await checked(id, graphId, 'attendees,isOrganizer,body');
    const body = { ...changes };
    if (body.attendees) body.attendees = [...body.attendees, ...(e.attendees || []).filter((a) => a.type === 'resource')];
    if (body.isOnlineMeeting) body.onlineMeetingProvider = 'teamsForBusiness';
    const invited = e.isOrganizer !== false && (body.attendees || e.attendees || []).some((a) => a.type !== 'resource');
    // Only with a change the attendees are sent anyway: a new description alone would send them an update.
    const sent = ['subject', 'body', 'start', 'end', 'isAllDay', 'location', 'attendees', 'isOnlineMeeting', 'recurrence'].some((k) => k in body);
    if (signature && invited && sent) {
      if (body.body) body.body = { contentType: 'text', content: withSignature(body.body.content, signature) };
      else if (e.body?.contentType === 'html') {
        const html = withSignatureHtml(e.body.content, signature);
        if (html != null) body.body = { contentType: 'html', content: html };
      } else if (!hasSignature(e.body?.content, signature)) body.body = { contentType: 'text', content: withSignature(e.body?.content, signature) };
    }
    const after = await graph(path, { Prefer: 'outlook.timezone="UTC"' }, { method: 'PATCH', body });
    return { id: after?.start?.dateTime ? occurrenceId(after, graphId) : id };
  }

  // Accept, tentatively accept or decline a meeting I was invited to, telling the organizer (with comment, and
  // `signature` after it) or not. proposedNewTime ({ start, end } as UTC instants) asks the organizer to move it,
  // as Outlook's Propose New Time does: only with a tentative or decline, always sent, and only when the organizer
  // allows new time proposals.
  async function respondEvent(id, graphId, action, { comment = '', sendResponse = true, signature = '', proposedNewTime = null } = {}) {
    needWrite('answer meetings');
    if (!['accept', 'tentativelyAccept', 'decline'].includes(action)) throw new CalendarError('Unknown response.', 400);
    const { path, e } = await checked(id, graphId, proposedNewTime ? 'allowNewTimeProposals,organizer' : '');
    const body = { comment, sendResponse };
    if (proposedNewTime) {
      if (action === 'accept') throw new CalendarError('A new time can only be proposed with a tentative or a decline.', 400);
      if (e.allowNewTimeProposals === false) {
        throw new CalendarError(`${e.organizer?.emailAddress?.name || 'The organizer'} doesn't allow new time proposals for this meeting.`, 400);
      }
      const at = (iso) => ({ dateTime: new Date(iso).toISOString().slice(0, 19), timeZone: 'UTC' });
      body.proposedNewTime = { start: at(proposedNewTime.start), end: at(proposedNewTime.end) };
      body.sendResponse = true;
    }
    if (body.sendResponse) body.comment = withSignature(comment, signature);
    await graph(`${path}/${action}`, {}, { method: 'POST', body });
  }

  // Outlook's category list, so SF Desk's categories get their colors (preset4 green, preset12 gray) where the add-in
  // hasn't made them yet. That needs MailboxSettings.ReadWrite, which SF Desk doesn't ask for: without it Microsoft
  // refuses and the categories are used without a color, as before. Tried once per category per run.
  const listed = new Set();
  async function ensureCategory(name, color) {
    if (!color || listed.has(name.toLowerCase())) return;
    listed.add(name.toLowerCase());
    try { await graph('/me/outlook/masterCategories', {}, { method: 'POST', body: { displayName: name, color } }); } catch { /* there already, or not allowed */ }
  }

  // Tag the meetings in my main calendar that match `wanted` ({ start, allDay, date, subject, tag }): the meeting at
  // the same start (same day when all-day) with the same or a similar subject, or the only one there. `tags` maps
  // each tag to its category ({ ds: { name, color }, none: ... }); a meeting gets its tag's category and loses the
  // others'. 'clear' takes them all off, 'unlinked' only the ds one. Meetings already that way are left alone.
  // A Deal Support covers one occurrence of a recurring meeting, so the ds category never stays on a series (where
  // every occurrence shows it): it comes off the series, and the occurrences that have one get it of their own.
  // Returns the counts.
  async function markCategory(fromIso, toIso, wanted, tags) {
    if (!canWrite(saved?.scope)) {
      throw new CalendarError(`${saved?.refresh_token ? 'Sign in to Microsoft 365 again' : 'Sign in to Microsoft 365'} to let SF Desk mark meetings in Outlook.`, 400);
    }
    const simple = (s) => String(s || '').replace(/^\s*\[backstory\b[^\]]*\]\s*/i, '').toLowerCase().replace(/[^a-z0-9&]+/g, ' ').trim();
    const mine = [];
    let url = '/me/calendarView?' + formBody({ startDateTime: fromIso, endDateTime: toIso,
      $select: 'id,subject,start,isAllDay,categories,isCancelled,type,seriesMasterId', $top: '200' });
    while (url) {
      const page = await graph(url, { Prefer: 'outlook.timezone="UTC"' });
      for (const e of page.value || []) {
        if (e.isCancelled) continue;
        mine.push({ id: e.id, subject: e.subject || '', allDay: !!e.isAllDay, categories: e.categories || [],
          day: e.start.dateTime.slice(0, 10), at: e.isAllDay ? null : Date.parse(e.start.dateTime + 'Z'),
          series: e.seriesMasterId || null, inherits: e.type === 'occurrence' });
      }
      url = page['@odata.nextLink'] || '';
    }
    const out = { marked: 0, already: 0, notFound: 0, failed: 0 };
    const lower = (s) => String(s).toLowerCase();
    const dsName = lower(tags.ds.name);
    const hits = [];
    const done = new Set();
    for (const w of wanted) {
      const at = Date.parse(w.start);
      const same = mine.filter((e) => e.allDay === !!w.allDay && (w.allDay ? e.day === w.date : e.at === at));
      const a = simple(w.subject);
      const hit = same.find((e) => { const b = simple(e.subject); return a && b && (a === b || a.includes(b) || b.includes(a)); }) ||
        (same.length === 1 ? same[0] : null);
      if (!hit) { out.notFound++; continue; }
      if (done.has(hit.id)) continue;
      done.add(hit.id);
      hits.push({ w, hit });
    }
    // The ds category off the series of these meetings; their plain occurrences had it from there.
    for (const series of new Set(hits.filter(({ hit }) => hit.series && hit.categories.some((c) => lower(c) === dsName)).map(({ hit }) => hit.series))) {
      try {
        const master = await graph(`/me/events/${encodeURIComponent(series)}?$select=categories`);
        const cats = master.categories || [];
        if (!cats.some((c) => lower(c) === dsName)) continue;
        await graph(`/me/events/${encodeURIComponent(series)}`, {}, { method: 'PATCH', body: { categories: cats.filter((c) => lower(c) !== dsName) } });
        out.series = (out.series || 0) + 1;
        for (const e of mine) if (e.series === series && e.inherits) e.categories = e.categories.filter((c) => lower(c) !== dsName);
      } catch (err) {
        out.failed++;
        out.error = err.message;
      }
    }
    for (const { w, hit } of hits) {
      const want = tags[w.tag]?.name;
      const drop = new Set((w.tag === 'unlinked' ? [tags.ds] : Object.entries(tags).filter(([k]) => k !== w.tag).map(([, t]) => t)).map((t) => lower(t.name)));
      const kept = hit.categories.filter((c) => !drop.has(lower(c)));
      const next = want && !kept.some((c) => lower(c) === lower(want)) ? [...kept, want] : kept;
      if (next.length === hit.categories.length && next.every((c, i) => c === hit.categories[i])) { if (want) out.already++; continue; }
      try {
        if (want) await ensureCategory(want, tags[w.tag].color);
        await graph(`/me/events/${encodeURIComponent(hit.id)}`, {}, { method: 'PATCH', body: { categories: next } });
        if (want) out.marked++; else out.cleared = (out.cleared || 0) + 1;
      } catch (err) {
        out.failed++;
        out.error = err.message;
      }
    }
    return out;
  }

  return { calendars, events, createEvent, deleteEvent, eventDetails, updateEvent, respondEvent, startSignIn, status, signOut, markCategory, markEnabled: MARK_ENABLED };
}
