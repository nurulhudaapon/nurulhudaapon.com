// Native-feeling navigation for the installed app, with sw.js: links are fetched as
// soon as a finger touches them, a newer copy of the open page is swapped in, and a
// loader shows when a navigation isn't instant.
(() => {
    if (!("serviceWorker" in navigator)) return;
    navigator.serviceWorker.register("/sw.js");

    const standalone = matchMedia("(display-mode: standalone)").matches || navigator.standalone === true;

    // The worker showed this page from cache and a different copy has arrived. Reload
    // to show it (from cache, so instantly), unless the reader is typing, or it was
    // just swapped: a page that differs on every request would otherwise loop.
    navigator.serviceWorker.addEventListener("message", (event) => {
        const data = event.data;
        if (data?.type !== "page-updated" || data.url !== location.href.split("#")[0]) return;
        const active = document.activeElement;
        if (active && (active.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(active.tagName))) return;
        const key = "pwa-swap:" + data.url;
        try {
            if (Date.now() - Number(sessionStorage.getItem(key) || 0) < 10_000) return;
            sessionStorage.setItem(key, String(Date.now()));
        } catch {}
        location.reload();
    });

    const target = (node) => {
        const link = node instanceof Element ? node.closest("a[href]") : null;
        if (!link || link.target === "_blank" || link.hasAttribute("download")) return null;
        const url = new URL(link.href, location.href);
        url.hash = "";
        if (url.origin !== location.origin || url.href === location.href.split("#")[0]) return null;
        return url.href;
    };

    // Fetching through the worker leaves the page in its cache for the tap.
    const warmed = new Set();
    const warm = (href) => {
        if (!href || warmed.has(href)) return;
        warmed.add(href);
        fetch(href, { credentials: "same-origin" }).catch(() => warmed.delete(href));
    };
    const onIntent = (event) => warm(target(event.target));
    addEventListener("touchstart", onIntent, { passive: true, capture: true });
    addEventListener("pointerdown", onIntent, { capture: true });
    let hover;
    addEventListener("mouseover", (event) => {
        clearTimeout(hover);
        const href = target(event.target);
        if (href) hover = setTimeout(() => warm(href), 65);
    });
    // In the app, also warm the navigation once the page is idle.
    if (standalone) {
        const idle = window.requestIdleCallback || ((fn) => setTimeout(fn, 1500));
        addEventListener("load", () => idle(() => {
            for (const link of document.querySelectorAll("nav a[href]")) warm(target(link));
        }));
    }

    // There is no browser loading bar in the app, so show one when a navigation
    // takes more than a moment.
    const loader = document.createElement("div");
    loader.className = "pwa-loader";
    loader.setAttribute("aria-hidden", "true");
    loader.innerHTML =
        '<svg viewBox="0 0 100 100"><circle class="pwa-loader-track" cx="50" cy="50" r="44"/>' +
        '<circle class="pwa-loader-arc" cx="50" cy="50" r="44"/>' +
        '<text x="50" y="50" dy="0.36em" text-anchor="middle">NH</text></svg>';
    document.body.append(loader);
    let pending;
    const loading = (on) => {
        clearTimeout(pending);
        if (on) pending = setTimeout(() => document.documentElement.classList.add("pwa-loading"), 150);
        else document.documentElement.classList.remove("pwa-loading");
    };
    document.addEventListener("click", (event) => {
        if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        if (target(event.target)) loading(true);
    });
    // Back/forward restores the page from memory with the loader still on.
    addEventListener("pageshow", () => loading(false));
})();
