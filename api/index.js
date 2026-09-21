// Vercel Serverless Entry Point
// This bridges the Vercel API environment to our existing Express app in the backend folder.
const app = require('../backend/server.js');

module.exports = app;
