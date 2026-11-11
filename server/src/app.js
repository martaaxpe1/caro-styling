const express = require('express');
const healthRoutes = require('./routes/health');
const authRoutes = require('./routes/auth');
const meRoutes = require('./routes/me');

const app = express();

app.disable('x-powered-by');
app.use(express.json());

// Open to anyone.
app.use('/health', healthRoutes);
app.use('/auth', authRoutes);

// Signed in only: each route checks the session itself (src/middleware/signed-in.js).
app.use('/me', meRoutes);

// Anything else: the app always gets JSON back, never an HTML page.
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// If a route throws, answer with a short JSON error.
app.use((err, req, res, next) => {
  // A request the server could not read, like broken JSON. Not logged: the request
  // could hold a sign-in code or a token, and those are never logged.
  if (err.status >= 400 && err.status < 500) {
    return res.status(err.status).json({ error: 'The server could not read this request.' });
  }
  console.error(err);
  res.status(500).json({ error: 'Something went wrong on the server.' });
});

module.exports = app;
