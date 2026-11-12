// npm run backup
// Makes a backup of the database and every photo now, in DATA_DIR/backups/ (src/jobs/backup.js).

const fs = require('fs');
const { makeBackup, backups, backupDir } = require('../src/jobs/backup');

makeBackup()
  .then((file) => {
    console.log(`Backup made: ${file} (${(fs.statSync(file).size / 1e6).toFixed(1)} MB).`);
    console.log(`Backups kept in ${backupDir}: ${backups().join(', ')}`);
  })
  .catch((err) => {
    console.error('Backup failed:', err);
    process.exitCode = 1;
  });
