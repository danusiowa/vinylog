// VinyLog · service worker
// Dzięki niemu aplikacja instaluje się na telefonie i szybciej się otwiera.
// Strona (index.html) idzie zawsze najpierw z sieci, więc nowa wersja apki
// pojawia się od razu; kopia z pamięci jest tylko na wypadek braku internetu.
// Dane z Supabase, Discogs, MusicBrainz i okładki NIE są tu zapisywane.

const VERSION = "vinylog-v1";
const SHELL = ["./", "./manifest.webmanifest", "./icons/icon-192.png", "./icons/icon.svg"];
const CDN = ["https://fonts.googleapis.com", "https://fonts.gstatic.com", "https://cdn.jsdelivr.net"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

async function networkFirst(req) {
  const cache = await caches.open(VERSION);
  try {
    const res = await fetch(req);
    if (res.ok) cache.put(req.mode === "navigate" ? "./" : req, res.clone());
    return res;
  } catch {
    return (await cache.match(req.mode === "navigate" ? "./" : req)) || Response.error();
  }
}

async function cacheFirst(req) {
  const cache = await caches.open(VERSION);
  const hit = await cache.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok) cache.put(req, res.clone());
  return res;
}

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  const sameOrigin = url.origin === self.location.origin;

  if (req.mode === "navigate" || (sameOrigin && url.pathname.endsWith("/index.html"))) {
    e.respondWith(networkFirst(req));
  } else if (sameOrigin && url.pathname.startsWith(new URL("./", self.location).pathname)) {
    e.respondWith(networkFirst(req));          // ikony, manifest: świeże, gdy jest sieć
  } else if (CDN.includes(url.origin)) {
    e.respondWith(cacheFirst(req));            // czcionki i biblioteki w stałych wersjach
  }
  // Wszystko inne (Supabase, Discogs, okładki) idzie prosto do sieci.
});
