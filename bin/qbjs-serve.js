#!/usr/bin/env node
/*
 * qbjs-serve.js  --  minimal static web server for a built QBJS app.
 *
 *   node qbjs-serve.js [rootDir] [port]
 *
 * Environment overrides: QBJS_SERVE_ROOT, PORT (args take precedence).
 * Defaults: rootDir = current directory, port = 8080, host = 0.0.0.0.
 *
 * This is a self-contained, dependency-free server (adapted from QBJS's
 * tools/qbjs-webserver.js) so the runnable-container image stays tiny. It is a
 * plain file server for the static bundle -- not a general-purpose web server.
 */
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");

const host = "0.0.0.0";
const rootDir = path.resolve(process.argv[2] || process.env.QBJS_SERVE_ROOT || process.cwd());
const port = parseInt(process.argv[3] || process.env.PORT || "8080", 10);

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".htm": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".webmanifest": "application/manifest+json",
  ".wasm": "application/wasm",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".webp": "image/webp",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".wav": "audio/wav",
  ".mp3": "audio/mpeg",
  ".ogg": "audio/ogg",
  ".mp4": "video/mp4",
  ".webm": "video/webm",
  ".txt": "text/plain; charset=utf-8",
  ".bas": "text/plain; charset=utf-8",
  ".map": "application/json; charset=utf-8"
};

http.createServer((req, res) => {
  // Decode + strip query string, then resolve safely under rootDir.
  let urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
  if (urlPath === "/") { urlPath = "/index.html"; }

  const filePath = path.join(rootDir, path.normalize(urlPath));
  // Prevent path traversal outside the served root.
  if (!filePath.startsWith(rootDir)) {
    res.writeHead(403, { "Content-Type": "text/plain" });
    res.end("403 Forbidden");
    return;
  }

  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("404 Not Found");
      return;
    }
    const type = MIME[path.extname(filePath).toLowerCase()] || "application/octet-stream";
    res.writeHead(200, {
      "Content-Type": type,
      // Service workers need this header to control the page scope.
      "Service-Worker-Allowed": "/"
    });
    res.end(content);
  });
}).listen(port, host, () => {
  console.log(`QBJS app serving ${rootDir}`);
  console.log(`Listening at http://${host}:${port}/`);
});
