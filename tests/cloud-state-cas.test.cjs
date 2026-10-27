const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../tool/android_assets/cloud-state-cas.js'), 'utf8');
const window = {};
vm.runInNewContext(source, { window, Date, JSON, TypeError, Error });
const cas = window.MFAndroidCloudCAS;
assert.ok(cas, 'CAS helper should expose its API');

function fakeClient(initialRow) {
  const db = { row: initialRow && { ...initialRow }, calls: [] };
  const client = {
    from(table) {
      assert.equal(table, 'mediaflow_states');
      return {
        update(values) {
          const query = { op: 'update', values, filters: {}, select() { return this; },
            eq(key, value) { this.filters[key] = value; return this; },
            async maybeSingle() {
              db.calls.push({ op: this.op, values: this.values, filters: this.filters });
              if (!db.row || db.row.user_id !== this.filters.user_id ||
                  db.row.updated_at !== this.filters.updated_at) return { data: null, error: null };
              db.row = { ...db.row, ...this.values };
              return { data: { updated_at: db.row.updated_at }, error: null };
            } };
          return query;
        },
        insert(values) {
          const query = { op: 'insert', values, select() { return this; },
            async maybeSingle() {
              db.calls.push({ op: this.op, values: this.values, filters: {} });
              if (db.row && db.row.user_id === values.user_id) {
                return { data: null, error: { code: '23505', message: 'duplicate user row' } };
              }
              db.row = { ...values };
              return { data: { updated_at: db.row.updated_at }, error: null };
            } };
          return query;
        }
      };
    }
  };
  return { client, db };
}
const encode = async (state, json) => ({ encoded: JSON.parse(json), marker: 'encoded' });
const assertAccount = () => {};

(async () => {
  {
    const { client, db } = fakeClient({ user_id: 'account-a', state_data: { version: 1 }, updated_at: 'v1' });
    const result = await cas.update(client, 'account-a', 'v1', { version: 2 }, encode, assertAccount);
    assert.equal(result.written, true);
    assert.equal(db.row.state_data.encoded.version, 2);
    assert.equal(db.calls[0].filters.user_id, 'account-a');
    assert.equal(db.calls[0].filters.updated_at, 'v1');
    assert.equal(db.calls[0].op, 'update');
  }
  {
    const { client, db } = fakeClient({ user_id: 'account-a', state_data: { version: 2 }, updated_at: 'v2' });
    const before = JSON.stringify(db.row);
    const result = await cas.update(client, 'account-a', 'v1', { version: 3 }, encode, assertAccount);
    assert.equal(result.written, false, 'stale revision must be a conflict');
    assert.equal(JSON.stringify(db.row), before, 'stale writes must not alter cloud data');
  }
  {
    const { client, db } = fakeClient({ user_id: 'account-a', state_data: { version: 1 }, updated_at: 'v1' });
    await assert.rejects(() => cas.update(client, 'account-a', null, { version: 2 }, encode, assertAccount),
      /unknown; refusing an unconditional update/);
    assert.equal(db.calls.length, 0);
  }
  {
    const { client, db } = fakeClient({ user_id: 'account-a', state_data: { version: 1 }, updated_at: 'v1' });
    await assert.rejects(() => cas.update(client, 'account-a', 'v1', { version: 2 }, encode,
      () => { throw new Error('account switched'); }), /account switched/);
    assert.equal(db.calls.length, 0);
  }
  {
    const { client, db } = fakeClient({ user_id: 'account-a', state_data: { version: 1 }, updated_at: 'v1' });
    await assert.rejects(() => cas.insertIfAbsent(client, 'account-a', { version: 2 }, encode, assertAccount),
      error => error.code === '23505');
    assert.equal(db.row.state_data.version, 1, 'first-row insertion must never replace an existing account');
  }
  {
    const { client, db } = fakeClient(null);
    const result = await cas.insertIfAbsent(client, 'account-a', { version: 1 }, encode, assertAccount);
    assert.equal(result.written, true);
    assert.equal(db.row.user_id, 'account-a');
    assert.equal(db.row.state_data.encoded.version, 1);
  }
  console.log('MediaFlow cloud CAS: owner filter, stale revision rejection, no upsert, account fence, insert-if-absent — PASS');
})().catch(error => { console.error(error); process.exitCode = 1; });
