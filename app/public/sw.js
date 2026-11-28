// Makes the installed app feel native: pages open instantly from cache while a fresh
// copy is fetched, and the page is told when that copy differs so it can swap it in
// (see pwa.js). Offline, the cache is all there is.
const CACHE = "site-v2";
const ADMIN = /^\/admin(\/|$)/;
const UNCACHED = /^\/(auth|api|mcp|internal|calendar|\.well-known)(\/|$)/;
// After a form post, pages may show what it changed: skip the cache for a moment.
let freshUntil = 0;
// A page fetched moments ago (e.g. prefetched on touch) isn't fetched again.
const fetchedAt = new Map();

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
    if (url.origin !== self.location.origin) return;

    if (request.method !== "GET") {
        freshUntil = Date.now() + 10_000;
        // Signing in or out: cached admin pages belong to the old session.
        if (url.pathname.startsWith("/auth/")) event.waitUntil(forgetAdmin());
        return;
    }
    if (UNCACHED.test(url.pathname) || request.headers.has("range")) return;

    event.respondWith(staleWhileRevalidate(event, request));
});

async function staleWhileRevalidate(event, request) {
    const cache = await caches.open(CACHE);
    const cached = Date.now() < freshUntil ? undefined : await cache.match(request, { ignoreVary: true });
    // Kept to compare with the fresh copy; the browser reads `shown`.
    const shown = cached?.clone();
    if (cached && Date.now() - (fetchedAt.get(request.url) ?? 0) < 5_000) return shown;
    const network = fetch(request).then(async (response) => {
        if (!response.ok || response.type !== "basic") return response;
        fetchedAt.set(request.url, Date.now());
        await cache.put(request, response.clone());
        if (cached && request.mode === "navigate" && await differs(cached, response.clone())) {
            const client = await self.clients.get(event.resultingClientId || event.clientId);
            client?.postMessage({ type: "page-updated", url: request.url });
        }
        return response;
    });

    if (!cached) {
        try {
            return await network;
        } catch (err) {
            const fallback = request.mode === "navigate" ? await cache.match("/") : undefined;
            if (fallback) return fallback;
            throw err;
        }
    }
    event.waitUntil(network.catch(() => {}));
    return shown;
}

// Interactive components embed a per-render id in HTML comments, so comments
// don't count as a change.
async function differs(a, b) {
    const strip = (html) => html.replace(/<!--[\s\S]*?-->/g, "");
    return strip(await a.text()) !== strip(await b.text());
}

async function forgetAdmin() {
    const cache = await caches.open(CACHE);
    for (const request of await cache.keys()) {
        if (ADMIN.test(new URL(request.url).pathname)) await cache.delete(request);
    }
}
