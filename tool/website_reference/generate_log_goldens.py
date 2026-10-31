#!/usr/bin/env python3
"""Generate golden fixtures for native logging from the REAL MediaFlow website.

Runs the website's own Batch Log code (in "Progress Reached" mode, filled the way
its form fills rows) on fixed accounts at a fixed clock, and records the account
state before and after. test/logging_golden_test.dart requires the Flutter app to
produce the same records.

Needs: a packaged website folder made by the Beta 11 WebView packager (it exposes a
read-only state accessor), headless Chrome and Playwright.
  python3 legacy/v/mediaflowapp-v1.0.0-beta.11/tool/package_mediaflow.py --output /tmp/www
  python3 tool/website_reference/generate_log_goldens.py /tmp/www
"""
import copy, json, pathlib, sys
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "legacy/v/mediaflowapp-v1.0.0-beta.11/tests/e2e"))
import smoke  # noqa: E402  (serve() + fake Supabase)

OUT = ROOT / "test/fixtures"
DECODE = """async (value) => { if (!value || value.__mediaflowCompressed !== 'gzip') return value;
  const bytes = Uint8Array.from(atob(value.data), c => c.charCodeAt(0));
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
  return JSON.parse(await new Response(stream).text()); }"""
NOW = 1793433600000  # 2026-10-31T08:00:00Z


def base_account():
    seed = json.loads((pathlib.Path(__file__).parent / "seed-account.json").read_text())
    return copy.deepcopy(seed)


def item(seed, **kw):
    out = copy.deepcopy(seed)
    out.update(kw)
    return out


def scenarios():
    acct = base_account()
    proto = acct["library"][0]
    s = []

    # 1. Mixed batch: partial progress, completion (clamped), rewatch, planned title without total.
    a = copy.deepcopy(acct)
    a["library"] = [
        item(proto, id="lib_alpha", title="Test Anime Alpha", categoryId="seasonal", progress=3, total=12, status="active"),
        item(proto, id="lib_beta", title="Book Beta", categoryId="books", progress=18, total=20, status="active", startedAt=1793400000000),
        item(proto, id="lib_gamma", title="Movie Gamma", categoryId="movies", progress=1, total=1, status="completed", completedAt=1790000000000),
        item(proto, id="lib_delta", title="Planned Delta", categoryId="manga", progress=0, total=None, status="planned", startedAt=None, startedAtSource=None),
    ]
    s.append(("mixed-batch", a, [
        {"libraryId": "lib_alpha", "reached": 5},
        {"libraryId": "lib_beta", "reached": 25, "minutes": 50},
        {"libraryId": "lib_gamma", "reached": 1},
        {"libraryId": "lib_delta", "reached": 4},
    ], "golden batch"))

    # 2. Title with seasons: progress is spread across seasons.
    b = copy.deepcopy(acct)
    b["library"] = [item(proto, id="lib_seasons", title="Seasoned Show", categoryId="tv", progress=10, total=22,
                         status="active", seasonSource="manual", seasons=[
                             {"id": "s1", "number": 1, "name": "Season 1", "progress": 10, "total": 10, "source": "manual"},
                             {"id": "s2", "number": 2, "name": "Season 2", "progress": 0, "total": 12, "source": "manual"}])]
    b["sessions"] = []
    s.append(("seasons", b, [{"libraryId": "lib_seasons", "reached": 13}], ""))

    # 3. Streak: logs on the three previous days raise today's multiplier.
    c = copy.deepcopy(acct)
    c["library"] = [item(proto, id="lib_streak", title="Streak Manga", categoryId="manga", progress=40, total=None, status="active")]
    c["sessions"] = []
    for i, day in enumerate(["2026-10-28", "2026-10-29", "2026-10-30"]):
        c["sessions"].append({"id": f"old_{i}", "timestamp": NOW - (3 - i) * 86400000, "date": day, "categoryId": "manga",
                              "targetAmount": 5, "actualAmount": 5, "minutes": 30, "note": "", "status": "logged",
                              "unit": "chapters", "xp": 225, "healthStatus": "healthy", "source": "batch",
                              "titles": [{"title": "Streak Manga", "libraryId": "lib_streak", "qty": 5, "repeat": False,
                                          "loggedAt": NOW - (3 - i) * 86400000}]})
    s.append(("streak", c, [{"libraryId": "lib_streak", "reached": 46, "minutes": 40}], "streak day"))
    return s


def run(www):
    OUT.mkdir(parents=True, exist_ok=True)
    server = smoke.serve(pathlib.Path(www))
    url = f"http://127.0.0.1:{server.server_address[1]}/index.html"
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, **({"executable_path": __import__("os").environ["CHROME_PATH"]} if __import__("os").environ.get("CHROME_PATH") else {}))
        for name, account, rows, note in scenarios():
            account["savedAt"] = NOW - 3600000
            ctx = browser.new_context(viewport={"width": 1280, "height": 900}, timezone_id="UTC")
            ctx.route("**/assets/vendor/supabase-js-v2.js",
                      lambda r: r.fulfill(status=200, content_type="text/javascript", body=smoke.FAKE))
            page = ctx.new_page()
            page.clock.install(time=NOW / 1000)
            row = {"user_id": "00000000-0000-4000-8000-000000000001", "state_data": account,
                   "updated_at": "2026-10-31T07:00:00.000Z"}
            page.add_init_script("localStorage.setItem('__fakeCloud', JSON.stringify(%s));" % json.dumps(row))
            page.goto(url)
            page.wait_for_function("() => window.MFAndroidCompanion && window.MFAndroidCompanion.booted", timeout=30000)
            page.wait_for_timeout(1200)
            read = "async () => { const d=" + DECODE + "; return await d(JSON.parse(localStorage.getItem('__fakeCloud')).state_data); }"
            before = page.evaluate(read)
            page.evaluate("""([rows, note]) => {
                const S = window.MFAndroidCompanion.debugState();
                S.batchDraft = {rows: rows.map(() => ({libraryId: '', query: '', qty: 1, minutes: 0})),
                                note, date: new Date().toISOString().slice(0, 10)};
                rows.forEach((r, i) => {
                    App.selectBatchTitle(i, r.libraryId);                  // picking the title in the form
                    App.v179UpdateBatchProgress(i, r.reached);            // typing "reached"
                    if (r.minutes != null) S.batchDraft.rows[i].minutes = r.minutes;  // edited minutes
                });
                App.submitBatchLog();
            }""", [rows, note])
            page.wait_for_timeout(2500)
            after = page.evaluate(read)
            raw_after = page.evaluate("JSON.parse(localStorage.getItem('__fakeCloud')).state_data")
            if name == "mixed-batch" and isinstance(raw_after, dict) and raw_after.get("__mediaflowCompressed") == "gzip":
                (OUT / "website-compressed-state.json").write_text(json.dumps({"state_data": raw_after, "state": after}) + "\n")
            (OUT / f"log-{name}.json").write_text(json.dumps(
                {"now": NOW, "timezone": "UTC", "note": note, "rows": rows, "before": before, "after": after}, indent=1) + "\n")
            print(name, len(before["sessions"]), "->", len(after["sessions"]), "sessions")
            ctx.close()
        browser.close()
    server.shutdown()


if __name__ == "__main__":
    run(sys.argv[1])
