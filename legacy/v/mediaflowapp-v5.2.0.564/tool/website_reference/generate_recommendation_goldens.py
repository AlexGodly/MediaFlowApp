#!/usr/bin/env python3
"""Golden fixtures for MediaFlow Recommends + recommendation logging, recorded
from the REAL website (same setup as generate_log_goldens.py).

Each scenario sets a known account and task, drives the website's own logging
actions (App.openLogForm, App.addLogEntry, per-unit actions...), and records:
  before      account state before submitting
  task        S.currentTask at submit time
  logDraft    S.logDraft at submit time (what the app's engine must submit)
  after       account state after App.submitLog()
Task-engine scenarios run with Math.random fixed at 0.5 so the jitter is zero and
the pick is deterministic.

  python3 tool/website_reference/generate_recommendation_goldens.py /tmp/www
"""
import copy, json, os, pathlib, sys
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "legacy/v/mediaflowapp-v1.0.0-beta.11/tests/e2e"))
import smoke  # noqa: E402

OUT = ROOT / "test/fixtures"
NOW = 1793433600000  # 2026-10-31T08:00:00Z
DECODE = """async (value) => { if (!value || value.__mediaflowCompressed !== 'gzip') return value;
  const bytes = Uint8Array.from(atob(value.data), c => c.charCodeAt(0));
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
  return JSON.parse(await new Response(stream).text()); }"""


def account():
    seed = json.loads((pathlib.Path(__file__).parent / "seed-account.json").read_text())
    proto = seed["library"][0]

    def item(**kw):
        x = copy.deepcopy(proto)
        x.update(kw)
        return x

    seed["library"] = [
        item(id="lib_alpha", title="Test Anime Alpha", categoryId="seasonal", progress=3, total=12, status="active", priority="high"),
        item(id="lib_alpha2", title="Second Seasonal", categoryId="seasonal", progress=0, total=13, status="planned", priority="medium", startedAt=None, startedAtSource=None),
        item(id="lib_beta", title="Book Beta", categoryId="books", progress=18, total=20, status="active"),
        item(id="lib_gamma", title="Movie Gamma", categoryId="movies", progress=1, total=1, status="completed", completedAt=1790000000000),
        item(id="lib_movie2", title="Movie Two", categoryId="movies", progress=0, total=1, status="planned", startedAt=None, startedAtSource=None),
        item(id="lib_show", title="Seasoned Show", categoryId="tv", progress=10, total=22, status="active", seasonSource="manual",
             seasons=[{"id": "s1", "number": 1, "name": "Season 1", "progress": 10, "total": 10, "source": "manual"},
                      {"id": "s2", "number": 2, "name": "Season 2", "progress": 0, "total": 12, "source": "manual"}]),
    ]
    for s in seed["sessions"]:
        s["titles"][0]["libraryId"] = "lib_alpha"
    seed["activityLog"] = []
    seed["xpLedger"] = {k: {} for k in seed["xpLedger"]}
    seed["sessionActive"] = False
    seed["currentTask"] = None
    seed["respectState"] = {"version": 165, "noSkipStreak": 3, "noRerollStreak": 2, "bestNoSkipStreak": 5,
                            "bestNoRerollStreak": 4, "currentRerolls": 0, "totalSkips": 1, "totalRerolls": 2,
                            "lastRewardAt": NOW - 86400000, "modifiedAt": NOW - 86400000}
    seed.pop("resumeStateV285", None)
    seed["savedAt"] = NOW - 3600000
    return seed


def task(cat, mid, low=None, high=None, lib=None, title=None, unit="episodes", tid="task_fixed"):
    return {"id": tid, "categoryId": cat, "libraryId": lib, "title": title, "low": low or mid, "high": high or mid,
            "targetMid": mid, "unit": unit, "createdAt": NOW - 60000, "reasons": ["fixture"],
            "amountMultiplier": 1, "balanceRatio": 1}


# Each scenario: (name, settings patch, task or None, JS steps run before submit, submit?)
SCENARIOS = [
    ("rec-quick-progress", {"exactTitleRecommendations": True},
     task("seasonal", 2, lib="lib_alpha", title="Test Anime Alpha"),
     """App.openLogForm(); App.v369SwitchInterface('quick');
        S.entryDraft = {title: 'Test Anime Alpha', qty: 1, libraryId: 'lib_alpha', endProgress: 5};
        App.addLogEntry();
        S.logDraft.note = 'great episodes';""", True),
    ("rec-quick-mixed", {},
     task("books", 3, low=2, high=4, unit="chapters"),
     """App.openLogForm(); App.v369SwitchInterface('quick');
        S.entryDraft = {title: 'Book Beta', qty: 1, libraryId: 'lib_beta', endProgress: 20}; App.addLogEntry();
        S.entryDraft = {title: 'Test Anime Alpha', qty: 1, libraryId: 'lib_alpha', endProgress: 4}; App.addLogEntry();
        S.logDraft.minutes = 90;""", True),
    ("rec-not-followed", {},
     task("movies", 1, unit="movies"),
     """App.openLogForm(); App.v369SwitchInterface('quick');
        S.entryDraft = {title: 'Test Anime Alpha', qty: 1, libraryId: 'lib_alpha', endProgress: 4}; App.addLogEntry();""", True),
    ("rec-itemized-units", {},
     task("seasonal", 2, lib=None),
     """App.openLogForm();
        S.entryDraft = {title: 'Test Anime Alpha', qty: 1, libraryId: 'lib_alpha'}; App.addLogEntry();
        App.v369AddUnit(0); App.v369AddUnit(0);
        App.v369EditUnit(0, 0, 'duration-1', 21);
        App.v369EditUnit(0, 1, 'time', new Date(Date.now() - 3600000).toISOString());
        S.entryDraft = {title: 'Seasoned Show', qty: 1, libraryId: 'lib_show'}; App.addLogEntry();
        App.v369SelectSeason(1, 's2'); App.v369AddUnit(1);""", True),
    ("rec-itemized-last", {},
     task("tv", 3, unit="episodes"),
     """App.openLogForm();
        S.entryDraft = {title: 'Seasoned Show', qty: 1, libraryId: 'lib_show'}; App.addLogEntry();
        App.v394Switch(0, 'last'); App.v394ChooseSeason(0, 's2');""", "last"),
    ("rec-reroll-title", {"exactTitleRecommendations": True},
     task("seasonal", 2, lib="lib_alpha", title="Test Anime Alpha"),
     """App.v180RerollRecommendedTitle();
        App.openLogForm(); App.v369SwitchInterface('quick');
        S.entryDraft = {title: S.currentTask.title, qty: 1, libraryId: S.currentTask.libraryId, endProgress: 2}; App.addLogEntry();""", True),
    ("rec-new-title", {},
     task("seasonal", 1),
     """App.openLogForm(); App.v369SwitchInterface('quick');
        S.settings.v181Logging = Object.assign({}, S.settings.v181Logging || {}, {defaultMode: 'amount'});
        S.logDraft.v179Mode = 'amount';
        S.entryDraft = {title: 'Brand New Show', qty: 2, libraryId: null}; App.addLogEntry();""", True),
]

# Task-engine scenarios (Math.random() === 0.5): actions on an active task.
ENGINE = [
    ("engine-start", {}, None, "App.startSession();"),
    ("engine-start-exact", {"exactTitleRecommendations": True}, None, "App.startSession();"),
    ("engine-reroll", {}, task("seasonal", 2), "App.rotateTask();"),
    ("engine-skip", {}, task("seasonal", 2), "App.skipTask();"),
    ("engine-end", {}, task("seasonal", 2), "App.endSession();"),
]


def run(www):
    OUT.mkdir(parents=True, exist_ok=True)
    server = smoke.serve(pathlib.Path(www))
    url = f"http://127.0.0.1:{server.server_address[1]}/index.html"
    read = "async () => { const d=" + DECODE + "; return await d(JSON.parse(localStorage.getItem('__fakeCloud')).state_data); }"
    launch = {"headless": True}
    if os.environ.get("CHROME_PATH"):
        launch["executable_path"] = os.environ["CHROME_PATH"]
    with sync_playwright() as p:
        browser = p.chromium.launch(**launch)

        def open_page(acct, fixed_random):
            ctx = browser.new_context(viewport={"width": 1280, "height": 900}, timezone_id="UTC")
            ctx.route("**/assets/vendor/supabase-js-v2.js",
                      lambda r: r.fulfill(status=200, content_type="text/javascript", body=smoke.FAKE))
            page = ctx.new_page()
            page.on("dialog", lambda d: d.accept())
            page.clock.install(time=NOW / 1000)
            if fixed_random:
                page.add_init_script("Math.random = () => 0.5;")
            row = {"user_id": "00000000-0000-4000-8000-000000000001", "state_data": acct, "updated_at": "2026-10-31T07:00:00.000Z"}
            page.add_init_script("localStorage.setItem('__fakeCloud', JSON.stringify(%s));" % json.dumps(row))
            page.goto(url)
            page.wait_for_function("() => window.MFAndroidCompanion && window.MFAndroidCompanion.booted", timeout=30000)
            page.wait_for_timeout(1200)
            return ctx, page

        for name, settings, tsk, steps, submit in SCENARIOS:
            acct = account()
            acct["settings"].update(settings)
            if tsk:
                acct["currentTask"] = tsk
                acct["sessionActive"] = True
            ctx, page = open_page(acct, False)
            before = page.evaluate(read)
            page.evaluate("(code) => { const S = window.MFAndroidCompanion.debugState(); (new Function('S','App', code))(S, App); }", steps)
            if submit == "last":
                page.evaluate("App.v394SetQuantity(0, 3)")
                page.wait_for_timeout(300)
            snap = page.evaluate("() => { const S = window.MFAndroidCompanion.debugState(); return JSON.parse(JSON.stringify({task: S.currentTask, logDraft: S.logDraft, entryDraft: S.entryDraft, respectState: S.respectState, library: S.library})); }")
            page.evaluate("App.submitLog()")
            page.wait_for_timeout(2500)
            after = page.evaluate(read)
            (OUT / f"{name}.json").write_text(json.dumps({"now": NOW, "timezone": "UTC", "before": before,
                "task": snap["task"], "logDraft": snap["logDraft"], "libraryAtSubmit": snap["library"],
                "respectAtSubmit": snap["respectState"], "after": after}, indent=1) + "\n")
            new = [s for s in after["sessions"] if s["id"] not in {x["id"] for x in before["sessions"]}]
            print(name, "+%d sessions" % len(new), [(s["categoryId"], s["status"], s["actualAmount"], s["xp"]) for s in new])
            ctx.close()

        for name, settings, tsk, steps in ENGINE:
            acct = account()
            acct["settings"].update(settings)
            if tsk:
                acct["currentTask"] = tsk
                acct["sessionActive"] = True
            ctx, page = open_page(acct, True)
            before = page.evaluate(read)
            page.evaluate("(code) => { const S = window.MFAndroidCompanion.debugState(); (new Function('S','App', code))(S, App); }", steps)
            page.wait_for_timeout(2500)
            live = page.evaluate("() => { const S = window.MFAndroidCompanion.debugState(); return JSON.parse(JSON.stringify({task: S.currentTask, sessionActive: S.sessionActive, respectState: S.respectState})); }")
            after = page.evaluate(read)
            (OUT / f"{name}.json").write_text(json.dumps({"now": NOW, "timezone": "UTC", "random": 0.5, "before": before,
                "live": live, "after": after}, indent=1) + "\n")
            t = live["task"]
            print(name, "->", t and (t["categoryId"], t["low"], t["high"], t["targetMid"], t.get("title")), "respect", {k: live["respectState"][k] for k in ("noSkipStreak", "noRerollStreak", "currentRerolls", "totalSkips", "totalRerolls")})
            ctx.close()
        browser.close()
    server.shutdown()


if __name__ == "__main__":
    run(sys.argv[1])
