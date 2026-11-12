const express = require('express');
const healthRoutes = require('./routes/health');
const authRoutes = require('./routes/auth');
const meRoutes = require('./routes/me');
const storeRoutes = require('./routes/stores');
const placeRoutes = require('./routes/places');
const adminRoutes = require('./routes/admin');
const pieceRoutes = require('./routes/pieces');
const wardrobeRoutes = require('./routes/wardrobe');
const listRoutes = require('./routes/lists');

const app = express();

app.disable('x-powered-by');
// A new piece carries its photo and cut-out (about 5 MB as base64), so that route reads larger
// requests. Everything else keeps the usual small limit.
app.use('/me/pieces', express.json({ limit: '25mb' }));
app.use(express.json());

// Open to anyone.
app.use('/health', healthRoutes);
app.use('/auth', authRoutes);

// Signed in only: each route checks the session itself (src/middleware/signed-in.js).
app.use('/me/stores', storeRoutes);
app.use('/me/pieces', pieceRoutes);
app.use('/me/wardrobe', wardrobeRoutes);
app.use('/me', meRoutes);
app.use('/places', placeRoutes);
app.use('/lists', listRoutes);

// The admin only: checked on the server for every route (src/routes/admin.js).
app.use('/admin', adminRoutes);

// Anything else: the app always gets JSON back, never an HTML page.
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// If a route throws, answer with a short JSON error.
app.use((err, req, res, next) => {
  if (err.status === 413) {
    return res.status(413).json({ error: 'This photo is too large to send.' });
  }
  // A request the server could not read, like broken JSON. Not logged: the request
  // could hold a sign-in code or a token, and those are never logged.
  if (err.status >= 400 && err.status < 500) {
    return res.status(err.status).json({ error: 'The server could not read this request.' });
  }
  console.error(err);
  res.status(500).json({ error: 'Something went wrong on the server.' });
});

module.exports = app;
