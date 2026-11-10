const express = require('express');
const healthRoutes = require('./routes/health');

const app = express();

app.disable('x-powered-by');
app.use(express.json());

app.use('/health', healthRoutes);

// Anything else: the app always gets JSON back, never an HTML page.
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// If a route throws, answer with a short JSON error and log the details here.
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'Something went wrong on the server' });
});

module.exports = app;
