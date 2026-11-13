#!/usr/bin/env python3
"""Golden fixtures for Beta 14's account edits, recorded from the REAL website.

Runs the website's own code for: the title editor (edit + add), deleting a
History log, adding titles to a Collection and changing the Personal Order, on
fixed accounts at a fixed clock, and records the account before and after.
test/edit_golden_test.dart requires the app to write the same things.

  python3 tool/website_reference/generate_edit_goldens.py /path/to/packaged/www
"""
import copy, json, pathlib, sys
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "legacy/v/mediaflowapp-v1.0.0-beta.11/tests/e2e"))
import smoke  # noqa: E402

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from generate_log_goldens import DECODE, NOW, base_account, item  # noqa: E402

OUT = ROOT / "test/fixtures"


def account():
    acct = base_account()
    proto = acct["library"][0]
    acct["library"] = [
        item(proto, id="lib_alpha", title="Test Anime Alpha", categoryId="seasonal", progress=3, total=12, status="active",
             startedAt=1790000000000, startedAtSource="manual", coverUrl="", coverSource=""),
        item(proto, id="lib_beta", title="Book Beta", categoryId="books", progress=18, total=20, status="active"),
        item(proto, id="lib_gamma", title="Movie Gamma", categoryId="movies", progress=0, total=1, status="planned",
             startedAt=None, startedAtSource=None),
    ]
    acct["sessions"] = []
    for i, day in enumerate(["2026-10-29", "2026-10-30"]):
        acct["sessions"].append({"id": f"old_{i}", "timestamp": NOW - (2 - i) * 86400000, "date": day, "categoryId": "seasonal",
                                 "targetAmount": 2, "actualAmount": 1, "minutes": 24, "note": "", "status": "logged",
                                 "unit": "episodes", "xp": 34, "healthStatus": "healthy", "source": "batch",
                                 "titles": [{"title": "Test Anime Alpha", "libraryId": "lib_alpha", "qty": 1, "repeat": False,
                                             "loggedAt": NOW - (2 - i) * 86400000}]})
    acct["collections"] = [{"id": "col_one", "title": "Weekend", "description": "", "coverUrl": "",
                            "titleIds": ["lib_alpha"], "order": ["lib_alpha"], "autoBackground": True,
                            "createdAt": NOW - 86400000, "updatedAt": NOW - 86400000, "lastViewedAt": 0}]
    acct["orderPlan"] = {"titleIds": ["lib_alpha", "lib_beta"], "viewMode": "all", "categoryMode": "default",
                         "categoryOrder": [], "hiddenCategories": [], "modifiedAt": NOW - 86400000}
    return acct


SCENARIOS = {
    # Title editor: Completed, rating, a manual cover, new progress.
    "edit-title": """
        App.openLibraryModal('lib_alpha');
        const set=(id,v)=>{const el=document.getElementById(id); if(el){el.value=v; el.dispatchEvent(new Event('input',{bubbles:true}));}};
        set('l-status','completed'); set('l-progress','12'); set('l-rating','8.5'); set('l-cover','https://example.com/alpha.jpg');
        App.saveLibraryModal('lib_alpha');""",
    # Title editor: a brand-new title.
    "add-title": """
        App.openLibraryModal();
        const set=(id,v)=>{const el=document.getElementById(id); if(el){el.value=v; el.dispatchEvent(new Event('input',{bubbles:true}));}};
        set('l-title','Brand New Show'); set('l-category','seasonal'); set('l-status','planned'); set('l-total','10'); set('l-priority','high');
        App.saveLibraryModal();""",
    # History: delete one log (undoable, Library History entry).
    "delete-history": """App.deleteSession('old_0');""",
    # Collections page: add two titles.
    "collection-add": """
        const S=window.MFAndroidCompanion.debugState(); S.view='collections';
        App.v274OpenAddTitles('col_one'); App.v392AddCollectionTitle('lib_beta'); App.v392AddCollectionTitle('lib_gamma');""",
    # Personal Order page: add a title and reorder.
    "order-change": """
        const S=window.MFAndroidCompanion.debugState(); S.view='order';
        App.v392AddOrderTitle('lib_gamma'); App.v138MoveTitle('lib_beta', -1);""",
}


def run(www, only=None):
    OUT.mkdir(parents=True, exist_ok=True)
    server = smoke.serve(pathlib.Path(www))
    url = f"http://127.0.0.1:{server.server_address[1]}/index.html"
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        for name, script in SCENARIOS.items():
            if only and name not in only:
                continue
            acct = account()
            acct["savedAt"] = NOW - 3600000
            ctx = browser.new_context(viewport={"width": 1280, "height": 900}, timezone_id="UTC")
            ctx.route("**/assets/vendor/supabase-js-v2.js",
                      lambda r: r.fulfill(status=200, content_type="text/javascript", body=smoke.FAKE))
            page = ctx.new_page()
            page.clock.install(time=NOW / 1000)
            page.clock.pause_at(NOW / 1000)
            row = {"user_id": "00000000-0000-4000-8000-000000000001", "state_data": acct,
                   "updated_at": "2026-10-31T07:00:00.000Z"}
            page.add_init_script("localStorage.setItem('__fakeCloud', JSON.stringify(%s));" % json.dumps(row))
            page.goto(url)
            page.clock.resume()
            page.wait_for_function("() => window.MFAndroidCompanion && window.MFAndroidCompanion.booted", timeout=30000)
            page.wait_for_timeout(1500)
            read = "async () => { const d=" + DECODE + "; return await d(JSON.parse(localStorage.getItem('__fakeCloud')).state_data); }"
            pick = ("() => { const S=window.MFAndroidCompanion.debugState(); const o={};"
                    " for (const k of ['library','sessions','completionTimeline','xpLedger','activityLog','collections','collectionTombstones','orderPlan','settings','currentTask','sessionActive','categories'])"
                    " o[k]=JSON.parse(JSON.stringify(S[k]===undefined?null:S[k])); return o; }")
            page.evaluate(read)
            before = page.evaluate(pick)
            page.evaluate("() => { window.confirm = () => true; " + script + " }")
            page.wait_for_timeout(3000)
            after = page.evaluate(pick)
            cloud = page.evaluate(read)
            for k in ("library", "sessions", "xpLedger", "activityLog", "collections", "orderPlan"):
                if json.dumps(cloud.get(k), sort_keys=True) != json.dumps(after.get(k), sort_keys=True):
                    print("  note: cloud copy differs from memory for", k)
            (OUT / f"edit-{name}.json").write_text(json.dumps(
                {"now": NOW, "timezone": "UTC", "before": before, "after": after}, indent=1) + "\n")
            print(name, "ok")
            ctx.close()
        browser.close()
    server.shutdown()


if __name__ == "__main__":
    run(sys.argv[1], set(sys.argv[2:]) or None)
