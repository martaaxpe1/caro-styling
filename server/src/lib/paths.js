const fs = require('fs');
const path = require('path');

// Where the database (and, from T5, the photos) live.
// Locally: server/data/, which Git ignores. Online (T8): Render's disk, set in DATA_DIR.
const dataDir = process.env.DATA_DIR ? path.resolve(process.env.DATA_DIR) : path.join(__dirname, '..', '..', 'data');
const databaseFile = path.join(dataDir, 'caro.db');

fs.mkdirSync(dataDir, { recursive: true });

module.exports = { dataDir, databaseFile };
