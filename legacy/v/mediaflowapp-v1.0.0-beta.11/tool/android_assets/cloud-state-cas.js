/* MediaFlow Android: compare-and-swap writes to the EXISTING mediaflow_states row.
   No schema changes, new tables, or upserts that can overwrite a newer version. */
(function (root) {
  'use strict';

  async function update(client, userId, expectedUpdatedAt, state, encode, assertAccount) {
    if (!client || !userId || typeof encode !== 'function' ||
        typeof assertAccount !== 'function') {
      throw new TypeError('Cloud compare-and-swap arguments are incomplete.');
    }
    if (typeof expectedUpdatedAt !== 'string' || !expectedUpdatedAt) {
      throw new Error('The current cloud version is unknown; refusing an unconditional update.');
    }
    assertAccount();
    const json = JSON.stringify(state);
    const stateData = await encode(state, json);
    assertAccount();
    const nextUpdatedAt = new Date().toISOString();
    const result = await client.from('mediaflow_states')
      .update({ state_data: stateData, updated_at: nextUpdatedAt })
      .eq('user_id', userId)
      .eq('updated_at', expectedUpdatedAt)
      .select('updated_at')
      .maybeSingle();
    if (result && result.error) throw result.error;
    assertAccount();
    if (!result || !result.data) return { written: false, updatedAt: null };
    return {
      written: true,
      updatedAt: typeof result.data.updated_at === 'string'
        ? result.data.updated_at : nextUpdatedAt
    };
  }

  async function insertIfAbsent(client, userId, state, encode, assertAccount) {
    if (!client || !userId || typeof encode !== 'function' ||
        typeof assertAccount !== 'function') {
      throw new TypeError('Cloud insert arguments are incomplete.');
    }
    assertAccount();
    const json = JSON.stringify(state);
    const stateData = await encode(state, json);
    assertAccount();
    const nextUpdatedAt = new Date().toISOString();
    const result = await client.from('mediaflow_states')
      .insert({ user_id: userId, state_data: stateData, updated_at: nextUpdatedAt })
      .select('updated_at')
      .maybeSingle();
    if (result && result.error) throw result.error;
    assertAccount();
    if (!result || !result.data) return { written: false, updatedAt: null };
    return {
      written: true,
      updatedAt: typeof result.data.updated_at === 'string'
        ? result.data.updated_at : nextUpdatedAt
    };
  }

  root.MFAndroidCloudCAS = Object.freeze({
    update: update,
    insertIfAbsent: insertIfAbsent
  });
})(typeof window !== 'undefined' ? window : globalThis);
