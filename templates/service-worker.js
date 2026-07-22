/*
 * QBJS standalone-app service worker (offline / installable PWA support).
 *
 * This is a LEAN service worker scoped to a single exported QBJS app -- unlike
 * the QBJS IDE's service worker, it only precaches this app's runtime files.
 *
 * Bump CACHE_VERSION whenever you rebuild program.js or change any asset so the
 * new version is picked up (the old cache is deleted on activate).
 */
const CACHE_VERSION = "qbjs-app-v1";

// Files this app needs to run fully offline. Relative to the service worker
// scope, so the same list works at a domain root or in a subpath (GitHub Pages).
const PRECACHE_URLS = [
  "./",
  "index.html",
  "program.js",
  "qb.js",
  "vfs.js",
  "gx/gx.js",
  "gx/__gx_font_default.png",
  "gx/__gx_font_default_black.png",
  "pako.2.1.0.min.js",
  "qbjs.css",
  "qbjs.woff2",
  "fonts/WebPlus_IBM_EGA_8x8.woff",
  "logo.png",
  "play.png",
  "favicon.ico",
  "fullscreen.svg",
  "fullscreen-hover.svg",
  "manifest.json"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION)
      // Individual misses (e.g. an asset you removed) shouldn't fail the install.
      .then((cache) => Promise.all(
        PRECACHE_URLS.map((url) => cache.add(url).catch(() => {}))
      ))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

// Cache-first, falling back to network (and caching the result at runtime).
self.addEventListener("fetch", (event) => {
  if (!event.request.url.startsWith(self.location.origin)) { return; }
  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) { return cached; }
      return fetch(event.request).then((response) => {
        return caches.open(CACHE_VERSION).then((cache) => {
          cache.put(event.request, response.clone());
          return response;
        });
      });
    })
  );
});
