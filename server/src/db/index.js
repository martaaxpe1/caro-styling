const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const { databaseFile } = require('../lib/paths');
const { now, iso } = require('../lib/today');

const db = new Database(databaseFile);

// WAL lets the server read while it writes, and keeps the file safe if it stops mid-write.
db.pragma('journal_mode = WAL');
// SQLite only checks foreign keys when asked to, once for every connection.
db.pragma('foreign_keys = ON');

runMigrations();

// Runs every file in migrations/ that this database has not run yet, in number order,
// and notes each one in the migrations table. Each file runs completely or not at all.
// Never edit a migration once it is committed: change the database with a new numbered file.
function runMigrations() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS migrations (
      name TEXT PRIMARY KEY,
      ran_at TEXT NOT NULL
    ) STRICT
  `);

  const folder = path.join(__dirname, 'migrations');
  const done = new Set(db.prepare('SELECT name FROM migrations').pluck().all());
  const files = fs.readdirSync(folder).filter((file) => file.endsWith('.sql')).sort();

  for (const file of files) {
    if (done.has(file)) continue;
    const sql = fs.readFileSync(path.join(folder, file), 'utf8');
    db.transaction(() => {
      db.exec(sql);
      db.prepare('INSERT INTO migrations (name, ran_at) VALUES (?, ?)').run(file, iso(now()));
    })();
    console.log(`Database: ran migration ${file}`);
  }
}

module.exports = db;
