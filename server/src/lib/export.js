// Download everything (PRD sections 4 and 14): one member's data and photos as a zip file.
//
// The zip holds:
// - caro.json: every row the database keeps for this member, table by table, and their
//   account. Sign-in sessions are left out: they are only hashed keys, not the member's data.
// - photos/: the member's own photo files, as stored (photo as JPEG, cut-out and thumbnail
//   as WebP). The photo paths in caro.json end in these file names.
// - README.txt: what the files are.
//
// Only rows with this member's user_id and only their own photo folder go in, so a member
// never gets anyone else's data. yazl (a small package) writes the zip as it is sent.

const fs = require('fs');
const path = require('path');
const yazl = require('yazl');
const db = require('../db');
const { absolute } = require('./photos');
const { now, iso } = require('./today');

const LEFT_OUT = new Set(['sessions']);

// The tables that hold a member's data: every one with a user_id column.
function memberTables() {
  const tables = db
    .prepare(`SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name`)
    .pluck()
    .all();
  return tables.filter(
    (table) => !LEFT_OUT.has(table) && db.prepare(`PRAGMA table_info(${table})`).all().some((column) => column.name === 'user_id')
  );
}

// Everything the database keeps for this member, as plain JSON.
function memberData(userId) {
  const account = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
  const tables = {};
  for (const table of memberTables()) {
    tables[table] = db.prepare(`SELECT * FROM ${table} WHERE user_id = ?`).all(userId);
  }
  const city = account.city_id ? db.prepare('SELECT * FROM cities WHERE id = ?').get(account.city_id) : null;
  return { exportedAt: iso(now()), account, city, tables };
}

const README = [
  'Your Caro data',
  '',
  'caro.json holds everything Caro keeps for you, table by table: your set-up, occasions,',
  'seasons, stores, pieces and their details, looks, inspirations, To find, and your AI actions.',
  '',
  'photos/ holds your photos: each piece as a photo (JPEG), a cut-out and a thumbnail (WebP),',
  'your photos wearing your looks, and your inspirations (JPEG, with a thumbnail).',
  'In caro.json, a piece points at its files by name.',
  '',
].join('\n');

// The zip for one member, as a yazl ZipFile. Pipe zip.outputStream to where it should go.
function memberZip(userId) {
  const zip = new yazl.ZipFile();
  zip.addBuffer(Buffer.from(JSON.stringify(memberData(userId), null, 2)), 'caro/caro.json');
  zip.addBuffer(Buffer.from(README), 'caro/README.txt');

  const folder = absolute(path.join('photos', String(userId)));
  if (fs.existsSync(folder)) {
    for (const name of fs.readdirSync(folder).sort()) {
      const file = path.join(folder, name);
      if (fs.statSync(file).isFile()) zip.addFile(file, `caro/photos/${name}`);
    }
  }

  zip.end();
  return zip;
}

module.exports = { memberZip, memberData };
