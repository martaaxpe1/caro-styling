// The nightly backup (PRD section 14): the database and every photo in one zip file.
//
// - The database is copied with SQLite's own backup, which gives a complete, consistent copy
//   even while the server is writing to it.
// - The zip goes in DATA_DIR/backups/, named like caro-2026-11-12.zip. The last 3 are kept.
// - The server checks every hour and makes a new one when the newest is a day old, so a
//   restart (every deploy restarts the server) never skips a night or makes two.
// - `npm run backup` makes one now, by hand.
//
// Online, Render also keeps its own daily snapshot of the whole disk for 7 days.
// A backup holds everyone's data, so it is never served by any route.

const fs = require('fs');
const path = require('path');
const yazl = require('yazl');
const db = require('../db');
const { dataDir } = require('../lib/paths');
const { now, iso, DAY, HOUR } = require('../lib/today');

const backupDir = path.join(dataDir, 'backups');
const KEEP = 3;

// The backups there are, newest first.
function backups() {
  if (!fs.existsSync(backupDir)) return [];
  return fs
    .readdirSync(backupDir)
    .filter((name) => /^caro-\d{4}-\d{2}-\d{2}\.zip$/.test(name))
    .sort()
    .reverse();
}

// Every file under a folder, with its path relative to that folder.
function filesIn(folder, prefix = '') {
  if (!fs.existsSync(folder)) return [];
  return fs.readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const relative = path.join(prefix, entry.name);
    if (entry.isDirectory()) return filesIn(path.join(folder, entry.name), relative);
    return entry.isFile() ? [relative] : [];
  });
}

// Makes a backup now and returns its file path.
async function makeBackup() {
  fs.mkdirSync(backupDir, { recursive: true });
  const name = `caro-${iso(now()).slice(0, 10)}.zip`;
  const databaseCopy = path.join(backupDir, 'caro-copy.db');
  const partial = path.join(backupDir, `${name}.part`);

  await db.backup(databaseCopy);
  try {
    const zip = new yazl.ZipFile();
    zip.addFile(databaseCopy, 'caro.db');
    const photos = path.join(dataDir, 'photos');
    for (const file of filesIn(photos)) {
      zip.addFile(path.join(photos, file), path.join('photos', file));
    }
    zip.end();

    // Written under another name first, so a half-written file never looks like a backup.
    await new Promise((resolve, reject) => {
      const out = fs.createWriteStream(partial);
      zip.outputStream.on('error', reject).pipe(out).on('finish', resolve).on('error', reject);
    });
    fs.renameSync(partial, path.join(backupDir, name));
  } finally {
    fs.rmSync(databaseCopy, { force: true });
    fs.rmSync(partial, { force: true });
  }

  for (const old of backups().slice(KEEP)) fs.rmSync(path.join(backupDir, old));
  return path.join(backupDir, name);
}

// A new backup is due when there is none, or the newest is from a day ago or more.
function backupDue() {
  const newest = backups()[0];
  if (!newest) return true;
  const madeAt = fs.statSync(path.join(backupDir, newest)).mtime;
  return Date.now() - madeAt.getTime() >= DAY - HOUR;
}

let running = false;
async function backUpIfDue() {
  if (running || !backupDue()) return;
  running = true;
  try {
    const file = await makeBackup();
    const megabytes = (fs.statSync(file).size / 1e6).toFixed(1);
    console.log(`Backup: ${path.basename(file)} (${megabytes} MB).`);
  } catch (err) {
    console.error('Backup failed:', err);
  } finally {
    running = false;
  }
}

function startNightlyBackup() {
  backUpIfDue();
  setInterval(backUpIfDue, HOUR);
}

module.exports = { makeBackup, backups, backupDir, startNightlyBackup };
