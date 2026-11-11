// Opens the local SQLite file for the desktop server (better-sqlite3); the queries are in store.js.

import Database from 'better-sqlite3';
import fs from 'node:fs';
import path from 'node:path';
import { createStore } from './store.js';

export function openDb(file) {
  if (file !== ':memory:') fs.mkdirSync(path.dirname(file), { recursive: true });
  return createStore(new Database(file));
}
