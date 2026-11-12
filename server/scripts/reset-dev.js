// npm run reset-dev
// Deletes the local database and photos, and seeds a fresh one. Only on this Mac: it refuses to run
// online, where the database holds members' real wardrobes.

const fs = require('fs');
const path = require('path');
const { databaseFile, dataDir } = require('../src/lib/paths');

// Render sets RENDER on its servers, so this refuses there even if NODE_ENV were forgotten.
if (process.env.NODE_ENV === 'production' || process.env.RENDER) {
  console.error('reset-dev deletes the database, so it only runs on your Mac, never online. Nothing was deleted.');
  process.exit(1);
}

if (!(process.env.ADMIN_EMAIL || '').includes('@')) {
  console.error('Add your email to server/.env first, as a line like ADMIN_EMAIL=you@example.com');
  console.error('Nothing was deleted.');
  process.exit(1);
}

// The database file, plus the two working files SQLite keeps next to it while it is open.
for (const file of [databaseFile, `${databaseFile}-wal`, `${databaseFile}-shm`]) {
  fs.rmSync(file, { force: true });
}
// The photos belong to the members in that database, so they go too.
fs.rmSync(path.join(dataDir, 'photos'), { recursive: true, force: true });
console.log('Deleted the local database and photos.');

// Running the seed opens a new, empty database, builds the tables and fills it.
require('./seed');
