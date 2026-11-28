// Network first: the installed app always shows the live site, and the cache is only
// a fallback for when there is no connection. Signed-in, API and feed responses are
// never cached.
const CACHE = "site-v1";
const UNCACHED = /^\/(admin|auth|api|mcp|internal|calendar)(\/|$)/;

self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (event) => {
    event.waitUntil((async () => {
        for (const key of await caches.keys()) if (key !== CACHE) await caches.delete(key);
        await self.clients.claim();
    })());
});

self.addEventListener("fetch", (event) => {
    const request = event.request;
    const url = new URL(request.url);
    if (request.method !== "GET" || url.origin !== self.location.origin || UNCACHED.test(url.pathname)) return;

    event.respondWith((async () => {
        try {
            const response = await fetch(request);
            if (response.ok && response.type === "basic") {
                const copy = response.clone();
                event.waitUntil(caches.open(CACHE).then((cache) => cache.put(request, copy)));
            }
            return response;
        } catch (err) {
            const cached = await caches.match(request) ?? (request.mode === "navigate" ? await caches.match("/") : undefined);
            if (cached) return cached;
            throw err;
        }
    })());
});
