// Reads the Mac's Exchange calendars (the Exchange account in System Settings > Internet Accounts) for
// Time Entry. Other calendars on the Mac (iCloud, Google, birthdays, subscriptions...) are left out. Uses
// a small EventKit helper (mac/calendar.swift), compiled with the Xcode Command Line Tools on first use
// into data/bin; the Mac app ships it prebuilt. Only available on macOS.

import { execFile } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export const isMac = process.platform === 'darwin';

const run = (cmd, args, timeout = 120_000) => new Promise((resolve, reject) => {
  execFile(cmd, args, { timeout, maxBuffer: 64 * 1024 * 1024 }, (err, stdout, stderr) => {
    if (err && !stdout) return reject(Object.assign(err, { stderr: String(stderr || '') }));
    resolve(String(stdout));
  });
});

class CalendarError extends Error {
  constructor(message, status = 502) { super(message); this.status = status; }
}

export function macCalendar(rootDir, dataDir) {
  const src = path.join(rootDir, 'mac', 'calendar.swift');
  const plist = path.join(rootDir, 'mac', 'Info.plist');
  // The Mac app ships the helper prebuilt (SF_DESK_CALENDAR_HELPER), so it needs no Command Line Tools.
  const prebuilt = process.env.SF_DESK_CALENDAR_HELPER;
  const bin = prebuilt || path.join(dataDir, 'bin', 'sfdesk-calendar');
  let ready = null;
  let exchangeIds = new Set();

  async function build() {
    if (prebuilt && fs.existsSync(prebuilt)) return;
    try {
      const stale = !fs.existsSync(bin) || fs.statSync(bin).mtimeMs < fs.statSync(src).mtimeMs;
      if (stale) {
        fs.mkdirSync(path.dirname(bin), { recursive: true });
        // The embedded Info.plist carries the text macOS shows when asking for calendar access.
        await run('xcrun', ['swiftc', '-O', '-swift-version', '5', src, '-o', bin,
          '-Xlinker', '-sectcreate', '-Xlinker', '__TEXT', '-Xlinker', '__info_plist', '-Xlinker', plist], 300_000);
      }
    } catch (err) {
      ready = null;
      console.warn(`Couldn't build the calendar helper: ${(err.stderr || err.message).trim().split('\n')[0]}`);
      throw new CalendarError('Reading your Exchange calendar needs the Xcode Command Line Tools when SF Desk runs from a ' +
        'checkout. Install them (xcode-select --install), then reload, or use the SF Desk app.');
    }
  }

  async function helper(args) {
    await (ready ||= build());
    const text = await run(bin, args).catch((err) => {
      throw new CalendarError(`Calendar helper failed: ${(err.stderr || err.message).trim()}`);
    });
    const data = JSON.parse(text || 'null');
    if (data?.error) throw new CalendarError(data.message, data.error === 'denied' ? 403 : 502);
    return data;
  }

  // [{ id, title, account, type }]: the Exchange account's calendars only.
  async function calendars() {
    const list = (await helper(['calendars'])).filter((c) => c.type === 'exchange');
    exchangeIds = new Set(list.map((c) => c.id));
    return list.sort((a, b) => a.account.localeCompare(b.account) || a.title.localeCompare(b.title));
  }

  // Events between two instants in the given Exchange calendars, each with a stable id for its occurrence.
  async function events(fromIso, toIso, ids) {
    if (ids.some((id) => !exchangeIds.has(id))) await calendars();
    const wanted = ids.filter((id) => exchangeIds.has(id));
    if (!wanted.length) throw new CalendarError('SF Desk only reads Exchange calendars. Pick one from the list.', 400);
    const list = await helper(['events', fromIso, toIso, wanted.join(',')]);
    return list.filter((e) => !e.canceled).map((e) => ({
      ...e,
      id: 'mac_' + crypto.createHash('sha1').update(`${e.uid}|${e.start}`).digest('hex').slice(0, 24),
    }));
  }

  return { calendars, events };
}
