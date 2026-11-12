const { execFileSync } = require('child_process');
const app = require('./app');
const { startDailyCleanUp } = require('./jobs/clean-up');
const pieceQueue = require('./jobs/piece-queue');

const port = process.env.PORT || 3000;

// The name other devices on the wifi use to find this Mac, for example Martas-MacBook-Pro-2.local
function macWifiName() {
  try {
    return execFileSync('scutil', ['--get', 'LocalHostName']).toString().trim() + '.local';
  } catch {
    return null;
  }
}

// Without a host, Express listens on every network address of this Mac,
// so the iPhone on the same wifi can reach it too.
app.listen(port, (err) => {
  if (err) {
    console.error(`Could not start on port ${port}: ${err.message}. Is another copy already running?`);
    process.exit(1);
  }

  console.log('Caro server running.');
  console.log(`  Simulator and browser: http://localhost:${port}/health`);

  const wifiName = process.env.NODE_ENV !== 'production' && macWifiName();
  if (wifiName) {
    console.log(`  iPhone on the same wifi: http://${wifiName}:${port}/health`);
  }

  // Expires old invitations and deletes members removed more than 30 days ago.
  startDailyCleanUp();
  // Reads the details of pieces that were still waiting when the server last stopped.
  pieceQueue.start();
});
