#!/usr/bin/env python3
"""End-to-end check of the packaged app in headless Chrome on a phone-sized screen.

Serves a packaged www/ folder, swaps the Supabase library for tests/e2e/fake-supabase.js,
then verifies: every website page is reachable, the Quick Log button opens the
single and batch logging forms, a logged title is saved to the (fake) cloud row,
and it is still there after a reload.

Usage: python tests/e2e/smoke.py <www-dir> [--shots <dir>]
       python tests/e2e/smoke.py --cdp http://127.0.0.1:9222   (attach to the desktop app,
       whose packaged www must already use fake-supabase.js as assets/vendor/supabase-js-v2.js)
"""
import argparse
import functools
import http.server
import json
import os
import pathlib
import sys
import threading

from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent
FAKE = (HERE / "fake-supabase.js").read_text(encoding="utf-8")


def serve(root):
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
    handler.log_message = lambda *a, **k: None
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def open_logging(page):
    """Tap the website's quick-actions button, then 'Add to Logging'."""
    page.click("#mf397-fab")
    page.wait_for_timeout(300)
    page.locator("#mf397-dock button", has_text="Add to Logging").first.click()
    page.wait_for_timeout(900)


def log_title(page, title, qty):
    """Switch to Quick logging, type a title, tap Add, then Save - like a person would."""
    if page.evaluate("(__S().logDraft||{}).v369Interface") != "quick":
        page.locator("#view-root button", has_text="Quick logging").first.click()
        page.wait_for_timeout(600)
    # Off-screen sections use content-visibility:auto (phone performance), so scroll
    # to the box first, exactly as a person scrolls down to it.
    page.evaluate("""() => {
        const box = [...document.querySelectorAll("#view-root input[placeholder^='Type a title']")]
            .find(i => i.getBoundingClientRect().width > 0);
        if (box) box.scrollIntoView({block: 'center'});
    }""")
    page.wait_for_timeout(300)
    form = page.locator("#view-root")
    title_box = form.locator("input[placeholder^='Type a title']:visible").first
    title_box.fill(title)
    # "Progress Reached" (progress mode) or a quantity box (amount mode).
    progress_box = form.locator("input[oninput*='v179UpdateEntryProgressDraft']:visible").first
    qty_box = form.locator("input[oninput*=\"updateEntryDraft('qty'\"]:visible").first
    if progress_box.count():
        progress_box.fill(str(qty))
    elif qty_box.count():
        qty_box.fill(str(qty))
    builder = page.locator("#view-root .v253-log-title-builder").first
    builder.locator("button", has_text="Add").first.click()
    page.wait_for_timeout(300)
    added = page.evaluate("(__S().logDraft.entries||[]).map(e => e.title + ' x' + e.qty)")
    print("  entries in session:", added)
    page.wait_for_timeout(400)
    page.locator("#view-root button", has_text="Save & get next task").first.click()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("www", nargs="?")
    ap.add_argument("--cdp", default=None, help="attach to a running app (desktop shell) instead")
    ap.add_argument("--shots", default=None)
    ap.add_argument("--chrome", default=os.environ.get("CHROME_PATH", ""))
    args = ap.parse_args()
    shots = pathlib.Path(args.shots) if args.shots else None
    if shots:
        shots.mkdir(parents=True, exist_ok=True)
    server = serve(pathlib.Path(args.www)) if not args.cdp else None
    url = f"http://127.0.0.1:{server.server_address[1]}/index.html" if server else None
    failures, errors = [], []

    def check(cond, label):
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            failures.append(label)

    with sync_playwright() as p:
        if args.cdp:
            browser = p.chromium.connect_over_cdp(args.cdp)
            ctx = browser.contexts[0]
            page = next(pg for pg in ctx.pages if pg.url.startswith("mediaflow://"))
            url = page.url
        else:
            launch = {"headless": True}
            if args.chrome:
                launch["executable_path"] = args.chrome
            browser = p.chromium.launch(**launch)
            ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2,
                                      is_mobile=True, has_touch=True)
            ctx.route("**/assets/vendor/supabase-js-v2.js",
                      lambda route: route.fulfill(status=200, content_type="text/javascript", body=FAKE))
            page = ctx.new_page()
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.add_init_script("""
            window.__S = () => window.MFAndroidCompanion.debugState();
            window.__decode = async (value) => {
              if (!value || value.__mediaflowCompressed !== 'gzip') return value;
              const bytes = Uint8Array.from(atob(value.data), c => c.charCodeAt(0));
              const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
              return JSON.parse(await new Response(stream).text());
            };
        """)

        def shot(name):
            if shots:
                page.screenshot(path=str(shots / f"{name}.png"))

        def booted():
            page.wait_for_function("() => window.MFAndroidCompanion && window.MFAndroidCompanion.booted === true",
                                   timeout=30000)
            page.wait_for_timeout(900)

        if args.cdp:
            page.evaluate("""() => {
                window.__S = () => window.MFAndroidCompanion.debugState();
                window.__decode = async (value) => {
                  if (!value || value.__mediaflowCompressed !== 'gzip') return value;
                  const bytes = Uint8Array.from(atob(value.data), c => c.charCodeAt(0));
                  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
                  return JSON.parse(await new Response(stream).text());
                };
            }""")
            print("  attached to", url, "| origin:", page.evaluate("location.origin"),
                  "| secure:", page.evaluate("isSecureContext"))
        else:
            page.goto(url)
        booted()
        shot("01-dashboard")
        check(page.evaluate("typeof window.MFAndroidCompanion.openLogging") == "function",
              "window.MFAndroidCompanion is defined (Beta 10 buttons were dead)")

        tabs = page.evaluate("[...document.querySelectorAll('.mobile-tabbar .mtab span')].map(s=>s.textContent.trim())")
        more = page.evaluate("[...document.querySelectorAll('#mobile-more-menu .mobile-more-item span')].map(s=>s.textContent.trim())")
        side = page.evaluate("[...document.querySelectorAll('.sidebar .nav-item, .sidebar nav button, .sidebar nav a')].map(s=>s.textContent.trim())")
        print("  tabs:", tabs, " more:", more, " sidebar:", side)
        everything = set(tabs) | set(more) | set(side)
        for label in ("Dashboard", "Library", "Statistics", "Settings"):
            check(any(label.lower() in t.lower() for t in everything), f"website page reachable: {label}")

        for view in ("library", "history", "stats", "collections", "order", "settings", "profile", "about", "dashboard"):
            page.evaluate(f"App.setView('{view}')")
            page.wait_for_timeout(350)
            ok = page.evaluate(f"__S().view === '{view}' && document.getElementById('view-root').innerHTML.length > 200")
            check(ok, f"page renders: {view}")
            if view in ("library", "stats", "settings"):
                shot(f"02-{view}")

        check(page.is_visible("#mf397-fab"), "website quick-actions button visible")
        sessions_before = page.evaluate("(__S().sessions||[]).length")
        open_logging(page)
        shot("04-log-form")
        check(page.evaluate("!!__S().logging && !!__S().logDraft && !!__S().logDraft.categoryId"), "logging form opens")

        scroll = page.evaluate("Math.max(window.scrollY, (document.querySelector('.main')||{}).scrollTop||0)")
        check(scroll > 300, f"screen scrolls to the logging form ({scroll}px)")
        check(page.locator("#view-root .log-form").first.is_visible(), "logging form is on screen")
        check(page.evaluate("!!(document.querySelector('#view-root details.v238-log-library')||{}).open"),
              "Logging Library (title search/add) is expanded")

        writes_before = page.evaluate("window.__fakeSupabaseLog.filter(x=>x.op==='update'||x.op==='insert').length")
        log_title(page, "Frieren: Beyond Journey's End", 2)
        page.wait_for_timeout(2500)
        shot("05-after-log")
        sessions_after = page.evaluate("(__S().sessions||[]).length")
        check(sessions_after == sessions_before + 1, f"log saved locally ({sessions_before} -> {sessions_after} sessions)")
        writes_after = page.evaluate("window.__fakeSupabaseLog.filter(x=>x.op==='update'||x.op==='insert').length")
        check(writes_after > writes_before, "log was written to the cloud row")
        cloud_sessions = page.evaluate("""async () => {
            const row = JSON.parse(localStorage.getItem('__fakeCloud')||'null');
            if (!row) return -1;
            const st = await __decode(row.state_data);
            return (st.sessions||[]).length;
        }""")
        check(cloud_sessions == sessions_after, f"cloud row holds the new log ({cloud_sessions} sessions)")
        status = page.evaluate("(document.getElementById('mf-android-companion-status')||{}).textContent||''")
        print("  sync status:", status)
        check("Synced" in status, "sync status shows Synced")

        # A batch draft saved by Beta 10 reopens inside the Dashboard.
        page.evaluate("App.setView('dashboard')")
        page.wait_for_timeout(300)
        page.evaluate("window.MFAndroidCompanion.openBatchLogging()")
        page.wait_for_timeout(600)
        shot("06-batch-form")
        check(page.evaluate("__S().view==='dashboard' && !!__S().logging && window.MFAndroidCompanion.logMode==='batch'"),
              "batch log form opens")
        check(page.evaluate("document.querySelector('#view-root').innerHTML.includes('Batch')"), "batch form rendered")
        page.evaluate("window.MFAndroidCompanion.closeBatch()")
        page.wait_for_timeout(300)
        check(page.evaluate("!__S().logging"), "batch form closes back to Dashboard")

        # Offline logging queues, then syncs on reconnect.
        page.evaluate("window.__fakeOffline = true")
        ctx.set_offline(True)
        page.wait_for_timeout(300)
        open_logging(page)
        log_title(page, "Offline title", 1)
        page.wait_for_timeout(1500)
        offline_sessions = page.evaluate("(__S().sessions||[]).length")
        check(offline_sessions == sessions_after + 1, "offline log saved on the device")
        check(page.evaluate("window.MFAndroidCompanion.pending === true"), "offline log queued for sync")
        ctx.set_offline(False)
        page.evaluate("window.__fakeOffline = false; window.dispatchEvent(new Event('online'))")
        page.wait_for_function("() => window.MFAndroidCompanion.pending === false && !window.MFAndroidCompanion.syncing",
                               timeout=20000)
        cloud_sessions = page.evaluate("""async () => {
            const row = JSON.parse(localStorage.getItem('__fakeCloud')||'null');
            const st = await __decode(row.state_data);
            return (st.sessions||[]).length;
        }""")
        check(cloud_sessions == offline_sessions, f"queued offline log uploaded on reconnect ({cloud_sessions})")

        # Reload: logs come back from the cloud row.
        page.reload()
        if args.cdp:
            page.wait_for_function("() => !!window.MFAndroidCompanion", timeout=30000)
            page.evaluate("""() => {
                window.__S = () => window.MFAndroidCompanion.debugState();
                window.__decode = async (value) => {
                  if (!value || value.__mediaflowCompressed !== 'gzip') return value;
                  const bytes = Uint8Array.from(atob(value.data), c => c.charCodeAt(0));
                  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
                  return JSON.parse(await new Response(stream).text());
                };
            }""")
        booted()
        shot("07-after-reload")
        check(page.evaluate("(__S().sessions||[]).length") == offline_sessions, "logs persist after reload")
        page.evaluate("App.setView('history')")
        page.wait_for_timeout(600)
        shot("08-history")
        check(page.evaluate("document.getElementById('view-root').textContent.includes('Frieren')"),
              "logged title appears in History")
        try:
            page.wait_for_function("() => { const c = window.MFAndroidCompanion; return !c.draftPending && !c.pending && !c.syncing && !c.draftSyncing; }", timeout=15000)
            settled = True
        except Exception:
            settled = False
        status = page.evaluate("(document.getElementById('mf-android-companion-status')||{}).textContent||''")
        print("  status after reload:", status, page.evaluate("(({draftPending,pending,attention,needsAuth,draftConflict})=>({draftPending,pending,attention,needsAuth,draftConflict}))(window.MFAndroidCompanion)"))
        check(settled and status == "Synced", "sync settles to Synced after reload")
        if not args.cdp:
            browser.close()
    if server:
        server.shutdown()

    real_errors = [e for e in errors if "serviceWorker" not in e and "ServiceWorker" not in e]
    for e in real_errors[:10]:
        print("  page error:", e[:300])
    check(not real_errors, "no uncaught page errors")
    print(json.dumps({"failures": failures}, indent=1))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
