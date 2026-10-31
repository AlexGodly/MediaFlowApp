/* Test-only stand-in for supabase-js v2. Never shipped in an app build.
   Simulates one signed-in account and the mediaflow_states row, including the
   updated_at compare-and-swap semantics of PostgREST `.eq()` filters.
   Cloud data lives in localStorage['__fakeCloud'] so it survives reloads. */
(function () {
  'use strict';
  const USER = {
    id: '00000000-0000-4000-8000-000000000001',
    email: 'tester@example.com',
    created_at: window.__FAKE_USER_CREATED_AT || new Date().toISOString()
  };
  const SESSION = { access_token: 'fake', refresh_token: 'fake', token_type: 'bearer', expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600, user: USER };
  const log = window.__fakeSupabaseLog = [];
  function cloud() { try { return JSON.parse(localStorage.getItem('__fakeCloud') || 'null'); } catch (_) { return null; } }
  function setCloud(row) { localStorage.setItem('__fakeCloud', JSON.stringify(row)); }
  const net = () => window.__fakeOffline ? Promise.reject(new TypeError('Failed to fetch')) : Promise.resolve();

  function query(table) {
    const q = { table, op: 'select', filters: [], values: null, single: false };
    const builder = {
      select() { if (q.op === 'select') q.op = 'select'; q.returning = true; return builder; },
      insert(v) { q.op = 'insert'; q.values = v; return builder; },
      update(v) { q.op = 'update'; q.values = v; return builder; },
      upsert(v) { q.op = 'upsert'; q.values = v; return builder; },
      delete() { q.op = 'delete'; return builder; },
      eq(col, val) { q.filters.push([col, val]); return builder; },
      maybeSingle() { q.single = true; return builder; },
      single() { q.single = true; return builder; },
      order() { return builder; }, limit() { return builder; },
      then(resolve, reject) { return net().then(() => run(q)).then(resolve, reject); }
    };
    return builder;
  }
  function matches(row, filters) {
    return filters.every(([col, val]) => {
      if (col === 'updated_at') return Date.parse(row.updated_at) === Date.parse(val);
      return String(row[col]) === String(val);
    });
  }
  function run(q) {
    if (q.table !== 'mediaflow_states') return { data: q.single ? null : [], error: null };
    const row = cloud();
    log.push({ op: q.op, filters: q.filters.map(f => f.join('=')).join('&'), at: Date.now() });
    if (q.op === 'select') {
      const hit = row && matches(row, q.filters) ? row : null;
      return { data: q.single ? hit : (hit ? [hit] : []), error: null };
    }
    if (q.op === 'insert') {
      if (row) return { data: null, error: { code: '23505', message: 'duplicate key' } };
      const next = Object.assign({}, q.values);
      setCloud(next);
      return { data: q.single ? { updated_at: next.updated_at } : [next], error: null };
    }
    if (q.op === 'upsert') {
      setCloud(Object.assign({}, row || {}, q.values));
      return { data: null, error: null };
    }
    if (q.op === 'update') {
      if (!row || !matches(row, q.filters)) return { data: null, error: null };
      const next = Object.assign({}, row, q.values);
      setCloud(next);
      return { data: q.single ? { updated_at: next.updated_at } : [next], error: null };
    }
    return { data: null, error: null };
  }
  const listeners = [];
  const auth = {
    getSession: () => net().then(() => ({ data: { session: SESSION }, error: null })),
    refreshSession: () => net().then(() => ({ data: { session: SESSION, user: USER }, error: null })),
    getUser: () => net().then(() => ({ data: { user: USER }, error: null })),
    onAuthStateChange(cb) {
      listeners.push(cb);
      setTimeout(() => cb('INITIAL_SESSION', SESSION), 0);
      return { data: { subscription: { unsubscribe() {} } } };
    },
    signInWithPassword: () => Promise.resolve({ data: { session: SESSION, user: USER }, error: null }),
    signUp: () => Promise.resolve({ data: { session: SESSION, user: USER }, error: null }),
    signOut: () => Promise.resolve({ error: null }),
    resetPasswordForEmail: () => Promise.resolve({ data: {}, error: null }),
    updateUser: () => Promise.resolve({ data: { user: USER }, error: null })
  };
  try {
    localStorage.setItem('sb-wgeijxfdpgehesxialxm-auth-token', JSON.stringify(SESSION));
  } catch (_) {}
  window.supabase = {
    createClient() {
      return {
        auth, from: query,
        rpc: () => Promise.resolve({ data: null, error: null }),
        functions: { invoke: () => Promise.resolve({ data: null, error: { message: 'offline test' } }) },
        channel() { const c = { on() { return c; }, subscribe() { return c; }, unsubscribe() {} }; return c; },
        removeChannel() {}
      };
    }
  };
})();
