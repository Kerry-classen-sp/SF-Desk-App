// Runs the iPhone app's core bundle (ios/build-core.sh) in a bare JavaScript sandbox, like JavaScriptCore
// (no Node or browser globals), with stand-ins for CoreRuntime.swift's `native` functions: SQLite through
// node:sqlite, Salesforce calls with the Salesforce CLI's access token. Then answers the same API calls as
// scripts/api-snapshot.mjs, so the two can be compared:
//
//   node ios/test/bundle-in-sandbox.mjs /tmp/sandbox && node scripts/api-snapshot.mjs --compare /tmp/before /tmp/sandbox

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import vm from 'node:vm';
import { PATHS } from '../../scripts/api-snapshot.mjs';

const out = process.argv[2];
fs.mkdirSync(out, { recursive: true });
const cli = (args) => JSON.parse(execFileSync('sf', [...args, '--json'], { encoding: 'utf8' })).result;
const token = () => {
  const org = cli(['org', 'display']);
  const t = !org.accessToken || /REDACTED/i.test(org.accessToken) ? cli(['org', 'auth', 'show-access-token']).accessToken : org.accessToken;
  return { accessToken: t, instanceUrl: org.instanceUrl.replace(/\/$/, '') };
};

const db = new DatabaseSync(path.join(out, 'sandbox.db'));
const stmts = new Map();
const native = {
  version: 'sandbox', hasCalendar: false,
  log: (level, text) => console.log(`[core ${level}]`, text),
  sql(op, sql, paramsJson) {
    try {
      if (op === 'exec') { db.exec(sql); return '{"result":null}'; }
      const p = JSON.parse(paramsJson);
      const st = stmts.get(sql) || stmts.set(sql, db.prepare(sql)).get(sql);
      const call = (fn) => (Array.isArray(p) ? st[fn](...p.map((v) => (typeof v === 'boolean' ? Number(v) : v))) : st[fn](p));
      const result = op === 'all' ? call('all') : op === 'get' ? call('get') ?? null : (call('run'), null);
      return JSON.stringify({ result }, (k, v) => (typeof v === 'bigint' ? Number(v) : v));
    } catch (err) { return JSON.stringify({ error: err.message }); }
  },
  fetch(reqJson, cb) {
    const r = JSON.parse(reqJson);
    fetch(r.url, { method: r.method, headers: r.headers, body: r.body ?? undefined })
      .then(async (res) => cb(JSON.stringify({ status: res.status, statusText: res.statusText,
        headers: Object.fromEntries(res.headers), body: await res.text() })))
      .catch((err) => cb(JSON.stringify({ error: err.message })));
  },
  refresh(cb) { cb(JSON.stringify(token())); },
  signOut() {},
  calendars(cb) { cb('[]'); },
  events(a, b, c, cb) { cb('[]'); },
};

const sandbox = vm.createContext({ native });
vm.runInContext(fs.readFileSync(new URL('../SFDesk/Generated/core-bundle.js', import.meta.url), 'utf8'), sandbox, { filename: 'core-bundle.js' });
const call = (fn, ...args) => new Promise((resolve) => sandbox[fn](...args, (json) => resolve(JSON.parse(json))));

const t = token();
const who = await call('sfdeskConnect', t.instanceUrl, t.accessToken, null);
console.log('connected as', who.user?.name || who.error);

const VOLATILE = /^(syncedAt|synced_at|at|now|today|generatedAt)$/;
const normalize = (v) => Array.isArray(v) ? v.map(normalize)
  : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, VOLATILE.test(k) ? '<volatile>' : normalize(v[k])]))
  : v;
for (const p of PATHS) {
  const r = await call('sfdeskHandle', JSON.stringify({ method: 'GET', url: p, headers: {} }));
  const body = JSON.parse(r.body || 'null');
  const cached = Object.keys(r.headers || {}).some((k) => k.toLowerCase() === 'x-sfdesk-cached');
  fs.writeFileSync(path.join(out, p.replace(/^\//, '').replace(/[^\w.-]+/g, '_') + '.json'),
    JSON.stringify({ status: r.status, cached, body: normalize(body) }, null, 1));
  console.log(String(r.status).padEnd(4), p);
}
