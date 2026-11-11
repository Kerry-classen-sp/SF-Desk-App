// Saves the JSON answers of SF Desk's read-only API calls, to check a change (e.g. to the shared core) left
// them alone. Signs in through /login (the Salesforce CLI login) on a running SF Desk.
//
//   node scripts/api-snapshot.mjs http://localhost:3107 /tmp/before
//   node scripts/api-snapshot.mjs --compare /tmp/before /tmp/after
//
// Fields that change between runs (sync times, "now") are blanked before saving.

import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const ACCOUNT = '0015000000ePariAAC', OPP = '006VO00000mVWETYA4', DS = 'a1XVO00000j6SZB2A2', TES = 'a1XVO00000jLdkP2AS';
export const PATHS = [
  '/me', '/meta', '/account-filters', '/hidden', '/prefs/accounts', '/deal-supports/meta',
  '/accounts?boat=all&team=mine', '/accounts?q=sinai&boat=all&team=all', `/accounts/${ACCOUNT}`, `/accounts/${ACCOUNT}/team`,
  `/accounts/${ACCOUNT}/deal-supports?since=2025-02-01`, `/opportunities/${OPP}/deal-supports`, `/opportunities/${OPP}/lead-se`,
  `/opportunities/${OPP}/related-requests`, `/deal-supports/${DS}`, '/users?q=classen',
  '/pipeline?boat=all&team=mine', '/pipeline?boat=all&team=mine&status=won', '/pipeline?boat=all&team=mine&status=lost',
  '/opportunities/open?q=sinai&limit=50', '/opportunities/open?q=renewal&limit=50&closed=1',
  '/my-time?from=2026-10-01&to=2026-10-31', '/team-ranking?from=2026-08-01&to=2026-10-31', '/tes?team=mine', `/tes/${TES}/updates`,
  '/calendar/sources', '/calendar?from=2026-10-26&to=2026-10-30&source=salesforce',
];

const VOLATILE = /^(syncedAt|synced_at|at|now|today|generatedAt)$/;
const normalize = (v) => Array.isArray(v) ? v.map(normalize)
  : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, VOLATILE.test(k) ? '<volatile>' : normalize(v[k])]))
  : v;
const fileOf = (p) => p.replace(/^\//, '').replace(/[^\w.-]+/g, '_') + '.json';

async function snapshot(base, out) {
  fs.mkdirSync(out, { recursive: true });
  const login = await fetch(base + '/login', { redirect: 'manual' });
  const cookie = (login.headers.getSetCookie?.() || []).map((c) => c.split(';')[0]).join('; ');
  for (const p of PATHS) {
    const r = await fetch(base + '/api' + p, { headers: { cookie } });
    const body = await r.json().catch(() => null);
    fs.writeFileSync(path.join(out, fileOf(p)), JSON.stringify({ status: r.status, cached: !!r.headers.get('X-SFDesk-Cached'), body: normalize(body) }, null, 1));
    console.log(String(r.status).padEnd(4), p);
  }
}

function compare(a, b) {
  let same = 0;
  for (const f of fs.readdirSync(a).filter((x) => x.endsWith('.json')).sort()) {
    const x = fs.readFileSync(path.join(a, f), 'utf8'), y = fs.existsSync(path.join(b, f)) ? fs.readFileSync(path.join(b, f), 'utf8') : null;
    if (x === y) { same++; continue; }
    console.log('DIFFERS', f, y == null ? '(missing)' : `(${x.length} vs ${y.length} bytes)`);
  }
  console.log(`${same} identical`);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv[2] === '--compare') compare(process.argv[3], process.argv[4]);
  else if (process.argv[2]) await snapshot(process.argv[2].replace(/\/$/, ''), process.argv[3]);
}
