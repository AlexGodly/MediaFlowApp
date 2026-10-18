import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read = p => readFileSync(p, 'utf8');
const widget = read('lib/features/full_app/full_mediaflow_screen.dart');
const app = read('lib/main.dart');
const manifest = JSON.parse(read('tool/releases/current.json'));
const doc = read('docs/FULL_APP_V504_PROTOTYPE.md');
assert.equal(manifest.tag, 'app-v1.0.0-beta.4');
assert.equal(manifest.basedOnMediaFlow, '504');
for (const s of ['https://alexgodly.github.io/MediaFlow/', 'InAppWebView(',
    'onReceivedError:', 'onProgressChanged:', 'onPopInvokedWithResult:',
    'request.isForMainFrame', 'domStorageEnabled: true']) {
  assert(widget.includes(s), 'full application integration missing: ' + s);
}
assert(app.includes("MEDIAFLOW_APP_MODE"));
assert(app.includes('const FullMediaFlowScreen()'));
assert(!/\.upsert\(|\.rpc\(|\.from\(/.test(widget),
    'full app shell must not introduce a second Supabase writer');
assert(doc.includes('unverified'), 'device limitations must be explicit');
console.log('Full website application, safe native fallback and beta4 manifest verified.');
