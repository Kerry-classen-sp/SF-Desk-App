// The iPhone app's side of the shared core, run in JavaScriptCore after core-bundle.js (see ios/build-core.sh).
// `native` is provided by CoreRuntime.swift:
//   native.log(level, text)
//   native.sql(op, sql, paramsJson) -> '{"result":...}' or '{"error":"..."}'   (synchronous; SQLiteStore.swift)
//   native.fetch(requestJson, callback(responseJson))                          (URLSession)
//   native.refresh(callback(resultJson))      renews the Salesforce access token (SalesforceAuth.swift)
//   native.signOut()                          forgets the saved login
//   native.sleep(ms, callback())
//   native.graphLoad() -> json or null, native.graphSave(json or null)   the Microsoft 365 sign-in (Keychain)
//   native.version

globalThis.console = {
  log: (...a) => native.log('info', a.map(String).join(' ')),
  warn: (...a) => native.log('warn', a.map(String).join(' ')),
  error: (...a) => native.log('error', a.map((x) => (x && x.stack) || String(x)).join(' ')),
};

// better-sqlite3's prepare / exec / pragma / transaction, over the app's SQLite file.
function nativeDb() {
  const call = (op, sql, params) => {
    const out = JSON.parse(native.sql(op, sql, JSON.stringify(params ?? [])));
    if (out.error) throw new Error(`SQLite: ${out.error}`);
    return out.result;
  };
  const args = (a) => (a.length === 1 && a[0] && typeof a[0] === 'object' && !Array.isArray(a[0]) ? a[0] : a);
  let depth = 0;
  return {
    prepare: (sql) => ({
      all: (...a) => call('all', sql, args(a)),
      get: (...a) => call('get', sql, args(a)) ?? undefined,
      run: (...a) => call('run', sql, args(a)),
    }),
    exec: (sql) => { call('exec', sql); },
    pragma: (text) => call('exec', 'PRAGMA ' + text),
    // Nested transactions run inside the outer one, as better-sqlite3's do.
    transaction: (fn) => (...a) => {
      if (depth++) { try { return fn(...a); } finally { depth--; } }
      call('exec', 'BEGIN');
      try {
        const result = fn(...a);
        call('exec', 'COMMIT');
        return result;
      } catch (err) {
        call('exec', 'ROLLBACK');
        throw err;
      } finally { depth--; }
    },
  };
}

const viaNative = (fn, ...args) => new Promise((resolve) => fn(...args, (json) => resolve(JSON.parse(json))));

// fetch for the core's Salesforce calls, made by URLSession (a page can't call Salesforce directly).
async function nativeFetch(url, { method = 'GET', headers = {}, body } = {}) {
  const r = await viaNative(native.fetch, JSON.stringify({ url, method, headers, body: body ?? null }));
  if (r.error) throw new TypeError(r.error);
  const lower = Object.fromEntries(Object.entries(r.headers || {}).map(([k, v]) => [k.toLowerCase(), v]));
  return {
    status: r.status, ok: r.status >= 200 && r.status < 300, statusText: r.statusText || '',
    headers: { get: (k) => lower[k.toLowerCase()] ?? null },
    text: async () => r.body ?? '',
    json: async () => JSON.parse(r.body || 'null'),
  };
}

const session = {
  destroy(done) {
    for (const k of Object.keys(session)) if (k !== 'destroy') delete session[k];
    done?.();
  },
};

async function refreshAccess(req) {
  const r = await viaNative(native.refresh);
  if (!r.accessToken) {
    delete req.session.sf;
    throw new HttpError(401, r.error || 'Your Salesforce session expired. Sign in again.');
  }
  req.session.sf.access_token = r.accessToken;
  if (r.instanceUrl) req.session.sf.instance_url = r.instanceUrl;
}

// Microsoft 365, with SailPoint's SF Desk app registration (as the desktop's .env.example).
const graphCal = graphCalendar({
  clientId: '7fa312ab-5012-408c-9ab8-f6ca82489fbb', tenant: '9c848b2a-49ba-4c39-9749-118d06717a84', markEnabled: true,
  fetch: nativeFetch,
  sleep: (ms) => new Promise((resolve) => native.sleep(ms, resolve)),
  load: () => { const json = native.graphLoad(); return json ? JSON.parse(json) : null; },
  save: (saved) => native.graphSave(saved ? JSON.stringify(saved) : null),
});

const router = createApi({
  router: miniRouter(), store: createStore(nativeDb()), refreshAccess, fetch: nativeFetch,
  version: native.version, platform: 'ios', isMac: false, useCli: false, graphCal,
  signOut: () => native.signOut(),
});

// The body as express.json() leaves it: parsed when it's JSON, otherwise {}.
function parseBody(headers, text) {
  const type = Object.entries(headers || {}).find(([k]) => k.toLowerCase() === 'content-type')?.[1] || '';
  if (!text || !/json/i.test(type)) return {};
  try { return JSON.parse(text); } catch { throw new HttpError(400, 'The request body isn\'t valid JSON.'); }
}

// One API request from the page: { method, url (after /api), headers, body (text) }. Replies { status, headers, body }.
globalThis.sfdeskHandle = (requestJson, reply) => {
  const r = JSON.parse(requestJson);
  Promise.resolve().then(() => router.handle({ ...r, body: parseBody(r.headers, r.body), session }))
    .then((out) => reply(JSON.stringify(out)), (err) => reply(JSON.stringify({ status: 500, headers: {}, body: JSON.stringify({ error: String(err) }) })));
};

// After signing in (or on launch with a saved login): look up who this is. `savedUser` is the last one seen,
// so the app opens on its saved copy when Salesforce can't be reached. Replies { user } or { error }.
globalThis.sfdeskConnect = (instanceUrl, accessToken, savedUserJson, reply) => {
  session.sf = { instance_url: instanceUrl, access_token: accessToken, native: true };
  loadUser({ session })
    .then(() => reply(JSON.stringify({ user: session.sf.user })))
    .catch((err) => {
      const saved = savedUserJson ? JSON.parse(savedUserJson) : null;
      if (saved && err.status >= 502) { session.sf.user = saved; return reply(JSON.stringify({ user: saved, offline: true })); }
      delete session.sf;
      reply(JSON.stringify({ error: err.message, status: err.status || 500 }));
    });
};

globalThis.sfdeskDisconnect = () => session.destroy();
