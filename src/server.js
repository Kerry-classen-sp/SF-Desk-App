// SF Desk — local Salesforce account & opportunity editor: the desktop server around the shared core (core.js).
// Talks to the Salesforce REST API using your own OAuth login (PKCE), or, when no
// SF_CLIENT_ID is set, the login you already have in the Salesforce CLI (`sf`).
// Runs on localhost only; tokens live in server memory for the session.
// Records loaded from Salesforce are kept in a local SQLite file (see db.js) so the
// last-seen data can still be shown when Salesforce can't be reached.

import 'dotenv/config';
import express from 'express';
import session from 'express-session';
import crypto from 'node:crypto';
import { execFile } from 'node:child_process';
import fs from 'node:fs';
import https from 'node:https';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApi, HttpError, loadUser, wrap } from './core.js';
import { openDb } from './db.js';
import { isMac, macCalendar } from './macCalendar.js';
import { isWindows, windowsCalendar } from './windowsCalendar.js';
import { graphCalendar, MARK_ENABLED } from './graphCalendar.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(__dirname, '..');
const { version: VERSION } = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));

const PORT = Number(process.env.PORT || 3000);
// The Outlook add-in needs HTTPS. When the certificate made by scripts/outlook-cert.sh is there, SF Desk also
// listens on https://localhost:HTTPS_PORT (see OUTLOOK.md).
const HTTPS_PORT = Number(process.env.HTTPS_PORT || 3443);
const CERT_DIR = process.env.SF_DESK_CERTS || path.join(ROOT, 'certs');
const LOGIN_URL = (process.env.SF_LOGIN_URL || 'https://login.salesforce.com').replace(/\/$/, '');
const CLIENT_ID = process.env.SF_CLIENT_ID;
const CLIENT_SECRET = process.env.SF_CLIENT_SECRET || '';
const REDIRECT_URI = `http://localhost:${PORT}/oauth/callback`;
const DB_FILE = process.env.SF_DESK_DB || path.join(ROOT, 'data', 'sf-desk.db');
// Without a client ID, sign in by borrowing the Salesforce CLI's login instead of running OAuth here.
const USE_CLI = !CLIENT_ID;
const SF_CLI = process.env.SF_CLI_PATH || 'sf';
const SF_TARGET_ORG = process.env.SF_TARGET_ORG || '';
// Where the CLI's browser sign-in goes (My Domain, for SSO), as in the desktop apps.
const CLI_INSTANCE_URL = process.env.SF_INSTANCE_URL || 'https://sailpoint.my.salesforce.com';

const b64url = (buf) => buf.toString('base64url');

const store = openDb(DB_FILE);
// This computer's Exchange calendar for Time Entry: the Mac's Exchange account, or classic Outlook's on Windows.
const localCal = isMac ? macCalendar(ROOT, path.dirname(DB_FILE)) : isWindows ? windowsCalendar(ROOT) : null;
const LOCAL_CAL_NAME = isWindows ? 'Outlook (classic)' : 'Mac calendar';
// Microsoft 365 calendars through Microsoft Graph, for the new Outlook (Windows; SF_DESK_GRAPH=1 elsewhere), and
// for marking meetings that have a Deal Support in Outlook (also on the Mac, once SF_DESK_OUTLOOK_MARK=1).
const graphCal = isWindows || (isMac && MARK_ENABLED) || process.env.SF_DESK_GRAPH ? graphCalendar(path.dirname(DB_FILE)) : null;

const app = express();
// Only this computer's own names: a web page whose domain is pointed at 127.0.0.1 (DNS rebinding) would
// otherwise count as this site, and could sign in and read and change everything through the API.
const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '[::1]'].flatMap((h) => [PORT, HTTPS_PORT].map((p) => `${h}:${p}`)));
app.use((req, res, next) => {
  if (LOCAL_HOSTS.has(String(req.headers.host || '').toLowerCase())) return next();
  res.status(421).type('text/plain').send('SF Desk only answers requests for localhost.');
});
app.use(express.json({ limit: '100kb' }));
// Separate sessions for the two listeners (express-session can't share a store between cookie settings).
// Outlook's task pane may be framed by Outlook, so the HTTPS cookie is SameSite=None; writes still need
// the X-SFDesk header (see the API's CSRF guard).
const sessionOpts = { secret: process.env.SESSION_SECRET || crypto.randomBytes(32).toString('hex'), resave: false, saveUninitialized: false };
const httpSession = session({ ...sessionOpts, cookie: { httpOnly: true, sameSite: 'lax' } });
const httpsSession = session({ ...sessionOpts, name: 'sfdesk.sid', cookie: { httpOnly: true, sameSite: 'none', secure: true } });
app.use((req, res, next) => (req.secure ? httpsSession : httpSession)(req, res, next));
app.use(express.static(path.join(ROOT, 'public')));

// ---------- Outlook add-in ----------

// The task pane is the app itself with Office.js added; the page sees the path and shows only the
// "create from this meeting" form.
const OFFICE_JS = '<script src="https://appsforoffice.microsoft.com/lib/1/hosted/office.js"></script>';
app.get('/outlook/pane', (req, res) => {
  const page = fs.readFileSync(path.join(ROOT, 'public', 'index.html'), 'utf8');
  res.type('html').set('Cache-Control', 'no-store').send(page.replace('<script src="xlsx.js"></script>', `${OFFICE_JS}\n<script src="/xlsx.js"></script>`));
});
// The add-in manifest to sideload, pointing at this server's HTTPS address.
app.get('/outlook/manifest.xml', (req, res) => {
  const xml = fs.readFileSync(path.join(ROOT, 'outlook', 'manifest.xml'), 'utf8');
  res.type('application/xml').set('Content-Disposition', 'attachment; filename="sf-desk-outlook.xml"')
    .send(xml.replaceAll('https://localhost:3443', `https://localhost:${HTTPS_PORT}`));
});

// ---------- Salesforce CLI login ----------

// The sf CLI reads SF_API_VERSION too, and rejects our "v62.0" form, so it doesn't get ours.
const { SF_API_VERSION: _apiVersion, ...CLI_ENV } = process.env;

// On Windows sf is a batch file (sf.cmd), which Node only runs through cmd.exe, so the command line
// is quoted by hand there. Our arguments are fixed words plus the org alias.
const winQuote = (a) => (/^[\w.:\\/@-]+$/.test(a) ? a : `"${String(a).replace(/"/g, '')}"`);

// Run an sf CLI command with --json and return its parsed output (errors become HttpErrors).
// `targetOrg: false` leaves out --target-org, for commands that don't take it.
function runCli(args, { targetOrg = true, timeout = 60_000 } = {}) {
  const target = targetOrg && SF_TARGET_ORG ? ['--target-org', SF_TARGET_ORG] : [];
  const all = [...args, '--json', ...target];
  const opts = { timeout, maxBuffer: 1024 * 1024, env: CLI_ENV, windowsHide: true };
  return new Promise((resolve, reject) => {
    const done = (err, stdout) => {
      // cmd.exe reports a missing sf as "not recognized" (exit code 1) rather than ENOENT.
      if (err?.code === 'ENOENT' || (isWindows && !String(stdout).trim() && /not recognized/i.test(String(err?.message)))) {
        return reject(new HttpError(400, 'Salesforce CLI (sf) not found. Install it, or set SF_CLI_PATH in .env. See README.md.'));
      }
      let out = null;
      try { out = JSON.parse(stdout); } catch { /* handled below */ }
      if (!out?.result) {
        const why = out?.message || err?.message || 'no result returned';
        return reject(new HttpError(401, `Salesforce CLI login not available: ${why}. ` +
          `Run "sf org login web${SF_TARGET_ORG ? ` --alias ${SF_TARGET_ORG}` : ' --set-default'}" and try again.`));
      }
      resolve(out.result);
    };
    if (isWindows) execFile([SF_CLI, ...all].map(winQuote).join(' '), [], { ...opts, shell: true }, done);
    else execFile(SF_CLI, all, opts, done);
  });
}

// Ask the sf CLI for a current access token. `org display` refreshes an expired token first.
// Newer CLI versions redact the token there, so fetch it with `org auth show-access-token` instead.
async function cliToken() {
  const org = await runCli(['org', 'display']);
  let token = org.accessToken;
  if (!token || /REDACTED/i.test(token)) token = (await runCli(['org', 'auth', 'show-access-token'])).accessToken;
  if (!token || !org.instanceUrl) {
    throw new HttpError(401, 'Salesforce CLI returned no access token. Run "sf org login web" and try again.');
  }
  return { access_token: token, instance_url: org.instanceUrl.replace(/\/$/, '') };
}

// ---------- OAuth (Web Server flow + PKCE) ----------

app.get('/login', (req, res, next) => {
  if (USE_CLI) return cliLogin(req, res).catch(next);
  // The OAuth callback is registered on http://localhost, whose session the task pane doesn't share.
  if (req.secure) return next(new HttpError(400, 'The Outlook add-in can only connect with the Salesforce CLI login. See OUTLOOK.md.'));
  const verifier = b64url(crypto.randomBytes(32));
  const challenge = b64url(crypto.createHash('sha256').update(verifier).digest());
  const state = b64url(crypto.randomBytes(16));
  req.session.pkce = { verifier, state };
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    code_challenge: challenge,
    code_challenge_method: 'S256',
    scope: 'api refresh_token',
    state,
  });
  res.redirect(`${LOGIN_URL}/services/oauth2/authorize?${params}`);
});

async function cliLogin(req, res) {
  req.session.sf = { ...(await cliToken()), cli: true };
  await loadUser(req);
  // The Outlook task pane comes back to itself.
  res.redirect(String(req.query.next || '').startsWith('/outlook/pane') ? '/outlook/pane' : '/');
}

app.get('/oauth/callback', wrap(async (req, res) => {
  const { code, state, error, error_description: desc } = req.query;
  if (error) throw new HttpError(400, `Salesforce login failed: ${error} ${desc || ''}`);
  const pkce = req.session.pkce;
  if (!pkce || state !== pkce.state) {
    throw new HttpError(400, 'Login state mismatch. Open http://localhost:' + PORT + ' and try again.');
  }
  delete req.session.pkce;

  const tok = await tokenRequest({
    grant_type: 'authorization_code',
    code,
    redirect_uri: REDIRECT_URI,
    code_verifier: pkce.verifier,
  });
  req.session.sf = {
    access_token: tok.access_token,
    refresh_token: tok.refresh_token,
    instance_url: tok.instance_url,
  };
  await loadUser(req);
  res.redirect('/');
}));

async function tokenRequest(params) {
  const body = new URLSearchParams({ client_id: CLIENT_ID, ...params });
  if (CLIENT_SECRET) body.set('client_secret', CLIENT_SECRET);
  const r = await fetch(`${LOGIN_URL}/services/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) {
    throw new HttpError(r.status === 400 ? 401 : 502,
      `Salesforce token error: ${data.error_description || data.error || r.statusText}`);
  }
  return data;
}

async function refreshAccess(req) {
  const t = req.session.sf;
  if (t.cli) {
    try {
      Object.assign(t, await cliToken());
    } catch {
      delete req.session.sf;
      throw new HttpError(401, 'Your Salesforce CLI login expired. Run "sf org login web" again, then reconnect.');
    }
    return;
  }
  try {
    const tok = await tokenRequest({ grant_type: 'refresh_token', refresh_token: t.refresh_token });
    t.access_token = tok.access_token;
    if (tok.instance_url) t.instance_url = tok.instance_url;
  } catch {
    delete req.session.sf;
    throw new HttpError(401, 'Your Salesforce session expired. Reconnect to continue.');
  }
}

// ---------- JSON API used by the page (core.js) ----------

const api = createApi({
  router: express.Router(), store, refreshAccess, version: VERSION, platform: process.platform, isMac, useCli: USE_CLI,
  localCal, localCalName: LOCAL_CAL_NAME, graphCal, markEnabled: MARK_ENABLED,
  // The CLI's browser sign-in, for when connecting finds no CLI login (or an expired one).
  cliLogin: () => runCli(['org', 'login', 'web', '--instance-url', CLI_INSTANCE_URL, ...(SF_TARGET_ORG ? ['--alias', SF_TARGET_ORG] : ['--set-default'])],
    { targetOrg: false, timeout: 15 * 60_000 }),
});

app.use('/api', api);

app.use((err, req, res, next) => {
  const status = err.status || 500;
  if (status >= 500) console.error(err);
  const message = status === 500 ? 'Unexpected server error (see terminal)' : err.message;
  if (req.originalUrl.startsWith('/api/')) return res.status(status).json({ error: message });
  res.status(status).type('text').send(message);
});

// Started by the Mac app (mac/app): stop when it quits or dies, which closes our stdin.
if (process.env.SF_DESK_APP) process.stdin.on('end', () => process.exit(0)).on('error', () => process.exit(0)).resume();

app.listen(PORT, 'localhost', () => {
  console.log(`SF Desk running at http://localhost:${PORT}`);
  if (USE_CLI) console.log(`No SF_CLIENT_ID set: signing in with the Salesforce CLI login${SF_TARGET_ORG ? ` for "${SF_TARGET_ORG}"` : ' (default org)'}.`);
  // The desktop apps open their window once this file appears.
  if (process.env.SF_DESK_READY) fs.writeFileSync(process.env.SF_DESK_READY, String(PORT));
});

// HTTPS for the Outlook add-in, only when its certificate has been made (scripts/outlook-cert.sh).
const certFile = path.join(CERT_DIR, 'localhost.pem'), keyFile = path.join(CERT_DIR, 'localhost-key.pem');
// An unreadable certificate (empty, half-written) only turns the add-in off; SF Desk itself keeps running.
if (fs.existsSync(certFile) && fs.existsSync(keyFile)) {
  try {
    https.createServer({ cert: fs.readFileSync(certFile), key: fs.readFileSync(keyFile) }, app)
      .on('error', (err) => console.error(`Outlook add-in HTTPS listener not started: ${err.message}`))
      .listen(HTTPS_PORT, 'localhost', () => console.log(`Outlook add-in served at https://localhost:${HTTPS_PORT}/outlook/pane`));
  } catch (err) {
    console.error(`Outlook add-in HTTPS listener not started: the certificate in ${CERT_DIR} can't be read (${err.message}). ` +
      'Make a new one with SF Desk > Set Up Outlook Add-in (or sh scripts/outlook-cert.sh --renew --trust).');
  }
}
