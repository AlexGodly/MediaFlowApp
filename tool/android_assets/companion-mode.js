/* MediaFlow Android Companion: recommendations, logging, local-first drafts and offline sync.
   Uses the existing v553 application logic and authenticated mediaflow_states row.
   No service-role key, new Supabase tables, or alternate cloud data model. */
(function () {
  'use strict';
  const DB_NAME = 'mediaflow-android-companion-v1';
  const STORE_NAME = 'snapshots';
  const DRAFT_PREFIX = 'mf_android_companion_draft_v1_';
  const QUEUE_PREFIX = 'mf_android_companion_queue_v1_';
  const BASE_PREFIX = 'mf_android_companion_cloud_base_v1_';
  const DRAFT_FIELD = '__mfAndroidCompanionDraftV1';
  const MAX_DRAFT_BYTES = 1024 * 1024;
  let dbPromise = null;
  let draftTimer = null;
  let cloudDraftTimer = null;
  let observer = null;
  const originalReadRecoveryCache = v115ReadRecoveryCache;
  const originalWriteRecoveryCache = v115WriteRecoveryCache;
  const companion = window.__mfAndroidCompanion = {
    active: !!window.__mfAndroidOfflineMode,
    pending: false,
    syncing: false,
    needsAuth: false,
    attention: false,
    draftPending: false,
    draftConflict: false,
    draftSyncing: false,
    conflictingCloudDraft: null,
    stateConflict: null,
    conflictResolution: null,
    lastCloudUpdatedAt: null,
    lastCloudProjection: null,
    logMode: 'single',
    hasSingleDraft: false,
    hasBatchDraft: false,
    booted: false,
    cachedSnapshot: null,
    navigate: navigate,
    openLogging: openLogging,
    openBatchLogging: openBatchLogging,
    toggleExactTitleRecommendations: toggleExactTitleRecommendations,
    syncNow: async function () {
      const stateOk = await reconcile(true);
      const draftOk = await syncDraftToCloud();
      return stateOk && draftOk;
    }
  };
  document.documentElement.dataset.mfAndroidCompanion = '1';
  if (typeof S !== 'undefined') S.offlineMode = companion.active;

  function uid() {
    try { return String(AUTH_USER && AUTH_USER.id || ''); } catch (_) { return ''; }
  }
  function queueKey(userId) { return QUEUE_PREFIX + String(userId || ''); }
  function draftKey(userId) { return DRAFT_PREFIX + String(userId || ''); }
  function queueMarkerExists(userId) {
    try {
      const value = JSON.parse(localStorage.getItem(queueKey(userId)) || 'null');
      return !!(value && value.userId === userId && value.pending === true);
    } catch (_) { return false; }
  }
  function markPending(userId, reason) {
    companion.pending = true;
    try {
      localStorage.setItem(queueKey(userId), JSON.stringify({
        version: 1, userId: userId, pending: true, queuedAt: Date.now(),
        reason: String(reason || 'Waiting for Supabase').slice(0, 160)
      }));
    } catch (_) {}
  }
  function clearPendingMarker(userId) {
    try { localStorage.removeItem(queueKey(userId)); } catch (_) {}
    companion.pending = false;
  }

  function sameJson(left, right) {
    const normalize = value => value === undefined ? null : value;
    try { return JSON.stringify(normalize(left)) === JSON.stringify(normalize(right)); }
    catch (_) { return left === right; }
  }
  function cloneJson(value) {
    if (value === undefined) return undefined;
    try { return JSON.parse(JSON.stringify(value)); } catch (_) { return value; }
  }
  function projectionFromState(state) {
    const value = state && typeof state === 'object' ? state : {};
    const keys = ['categories', 'categoryOrder', 'settings', 'currentTask',
      'sessionActive', 'profilePicture', 'stopwatch', 'malLink', 'orderPlan'];
    const result = {};
    keys.forEach(key => { result[key] = value[key] === undefined ? null : cloneJson(value[key]); });
    return result;
  }
  function baselineKey(userId) { return BASE_PREFIX + String(userId || ''); }
  function setCloudBaseline(userId, state, updatedAt) {
    if (!userId || !state || typeof updatedAt !== 'string' || !updatedAt) return;
    const projection = projectionFromState(state);
    companion.lastCloudUpdatedAt = updatedAt;
    companion.lastCloudProjection = projection;
    try {
      localStorage.setItem(baselineKey(userId), JSON.stringify({
        version: 1, userId: userId, updatedAt: updatedAt, projection: projection
      }));
    } catch (_) {}
  }
  function restoreCloudBaseline(userId, record) {
    if (companion.lastCloudUpdatedAt && companion.lastCloudProjection) return;
    try {
      const stored = JSON.parse(localStorage.getItem(baselineKey(userId)) || 'null');
      if (stored && stored.version === 1 && stored.userId === userId &&
          typeof stored.updatedAt === 'string' && stored.projection &&
          typeof stored.projection === 'object') {
        companion.lastCloudUpdatedAt = stored.updatedAt;
        companion.lastCloudProjection = stored.projection;
        return;
      }
    } catch (_) {}
    if (record && record.userId === userId &&
        typeof record.baseUpdatedAt === 'string' &&
        record.baseProjection && typeof record.baseProjection === 'object') {
      companion.lastCloudUpdatedAt = record.baseUpdatedAt;
      companion.lastCloudProjection = record.baseProjection;
    }
  }
  function readLocalDraft(userId) {
    if (!userId) return null;
    try {
      const value = JSON.parse(localStorage.getItem(draftKey(userId)) || 'null');
      if (!value || value.version !== 1 || value.userId !== userId ||
          !Number.isFinite(Number(value.savedAt)) || Number(value.savedAt) <= 0 ||
          Date.now() - Number(value.savedAt) > 90 * 24 * 60 * 60 * 1000) return null;
      return value;
    } catch (_) { return null; }
  }
  function draftContentKey(value) {
    if (!value || typeof value !== 'object') return '';
    const copy = Object.assign({}, value);
    delete copy.savedAt;
    delete copy.cloudSyncedAt;
    return JSON.stringify(copy);
  }
  function draftIsEligible(value) {
    return !!(value && (value.everHadDraft || value.singleDraftExists ||
      value.batchDraftExists || Number(value.cloudSyncedAt) > 0));
  }
  function cloudDraftCopy(value) {
    if (!value || typeof value !== 'object') return null;
    const copy = Object.assign({}, value);
    delete copy.cloudSyncedAt;
    return copy;
  }
  function storeLocalDraft(userId, value) {
    if (!userId || !value || value.userId !== userId) return false;
    try { localStorage.setItem(draftKey(userId), JSON.stringify(value)); return true; }
    catch (_) { return false; }
  }
  function markLocalDraftSynced(userId, sentDraft) {
    const current = readLocalDraft(userId);
    if (!current || !sentDraft || Number(current.savedAt) !== Number(sentDraft.savedAt) ||
        draftContentKey(current) !== draftContentKey(sentDraft)) return false;
    current.cloudSyncedAt = Number(current.savedAt);
    storeLocalDraft(userId, current);
    companion.draftPending = false;
    return true;
  }
  function captureCloudDraft(state, userId) {
    const remote = state && state[DRAFT_FIELD];
    if (!remote || remote.version !== 1 || remote.userId !== userId ||
        !Number.isFinite(Number(remote.savedAt)) || Number(remote.savedAt) <= 0) return;
    const cloud = cloudDraftCopy(remote);
    const local = readLocalDraft(userId);
    if (!local) {
      cloud.cloudSyncedAt = Number(cloud.savedAt);
      storeLocalDraft(userId, cloud);
      companion.draftPending = false;
      companion.draftConflict = false;
      companion.hasSingleDraft = !!cloud.singleDraftExists;
      companion.hasBatchDraft = !!cloud.batchDraftExists;
      return;
    }
    const localDirty = Number(local.savedAt) > Number(local.cloudSyncedAt || 0);
    const same = draftContentKey(local) === draftContentKey(cloud);
    if (same) {
      local.cloudSyncedAt = Math.max(Number(local.cloudSyncedAt) || 0, Number(cloud.savedAt));
      storeLocalDraft(userId, local);
      companion.draftPending = false;
      companion.draftConflict = false;
      return;
    }
    if (Number(cloud.savedAt) > Number(local.savedAt)) {
      if (localDirty) {
        companion.draftConflict = true;
        companion.conflictingCloudDraft = cloud;
        companion.draftPending = true;
      } else {
        cloud.cloudSyncedAt = Number(cloud.savedAt);
        storeLocalDraft(userId, cloud);
        companion.draftPending = false;
        companion.draftConflict = false;
        companion.hasSingleDraft = !!cloud.singleDraftExists;
        companion.hasBatchDraft = !!cloud.batchDraftExists;
        if (companion.booted) {
          restoreDraft();
          render();
        }
      }
    } else if (Number(cloud.savedAt) === Number(local.savedAt)) {
      companion.draftConflict = true;
      companion.conflictingCloudDraft = cloud;
      companion.draftPending = true;
    } else {
      companion.draftPending = localDirty || Number(local.savedAt) > Number(cloud.savedAt);
      if (companion.draftPending) scheduleCloudDraftSync();
    }
  }

  function mergeThreeWay(local, remote, base, path, conflicts, strategy) {
    const localChanged = !sameJson(local, base);
    const remoteChanged = !sameJson(remote, base);
    if (!localChanged && remoteChanged) return cloneJson(remote);
    if (localChanged && !remoteChanged) return cloneJson(local);
    if (!localChanged && !remoteChanged) return cloneJson(local === undefined ? remote : local);
    if (sameJson(local, remote)) return cloneJson(local);
    const objectLike = value => value && typeof value === 'object' && !Array.isArray(value);
    if (objectLike(local) && objectLike(remote) && objectLike(base)) {
      const result = {};
      const keys = new Set([...Object.keys(base), ...Object.keys(local), ...Object.keys(remote)]);
      keys.forEach(key => {
        result[key] = mergeThreeWay(local[key], remote[key], base[key],
          path ? path + '.' + key : key, conflicts, strategy);
      });
      return result;
    }
    if (strategy === 'local') return cloneJson(local);
    if (strategy === 'remote') return cloneJson(remote);
    conflicts.push(path);
    return cloneJson(local);
  }
  function mergeConcurrentStates(localState, remoteState, baseProjection, strategy) {
    const merged = mergeOfflineStates(localState, remoteState);
    const conflicts = [];
    const fields = ['categories', 'categoryOrder', 'currentTask', 'sessionActive',
      'profilePicture', 'stopwatch', 'malLink', 'orderPlan'];
    fields.forEach(key => {
      merged[key] = mergeThreeWay(localState[key], remoteState[key],
        baseProjection[key], key, conflicts, strategy);
    });
    merged.settings = mergeThreeWay(localState.settings || {}, remoteState.settings || {},
      baseProjection.settings || {}, 'settings', conflicts, strategy);
    return { state: merged, conflicts: conflicts };
  }
  function scheduleCloudDraftSync() {
    if (cloudDraftTimer !== null) clearTimeout(cloudDraftTimer);
    cloudDraftTimer = setTimeout(function () {
      cloudDraftTimer = null;
      if (navigator.onLine && uid()) syncDraftToCloud();
    }, 1800);
  }

  function isNetworkError(error) {
    const message = String(error && (error.message || error) || '');
    return navigator.onLine === false ||
      /failed to fetch|network|offline|load failed|err_internet_disconnected|connection reset|connection refused|timed out|timeout|aborted|fetch failed/i.test(message);
  }
  function requiresReauthentication(error) {
    const message = String(error && (error.message || error) || '');
    return /invalid.*refresh|refresh token.*invalid|invalid jwt|jwt expired|unauthorized|not authenticated|session.*reconnect|token.*expired/i.test(message);
  }
  function openDatabase() {
    if (!window.indexedDB) return Promise.reject(new Error('IndexedDB is not available on this device.'));
    if (dbPromise) return dbPromise;
    dbPromise = new Promise(function (resolve, reject) {
      const request = indexedDB.open(DB_NAME, 1);
      request.onupgradeneeded = function () {
        const db = request.result;
        if (!db.objectStoreNames.contains(STORE_NAME)) {
          db.createObjectStore(STORE_NAME, { keyPath: 'userId' });
        }
      };
      request.onsuccess = function () { resolve(request.result); };
      request.onerror = function () { reject(request.error || new Error('Could not open offline storage.')); };
      request.onblocked = function () { reject(new Error('Offline storage upgrade is blocked.')); };
    });
    return dbPromise;
  }
  async function readIdbRecord(userId) {
    const db = await openDatabase();
    return new Promise(function (resolve, reject) {
      const tx = db.transaction(STORE_NAME, 'readonly');
      const request = tx.objectStore(STORE_NAME).get(userId);
      request.onsuccess = function () { resolve(request.result || null); };
      request.onerror = function () { reject(request.error || new Error('Could not read the offline snapshot.')); };
    });
  }
  async function writeIdbRecord(record) {
    const db = await openDatabase();
    return new Promise(function (resolve, reject) {
      const tx = db.transaction(STORE_NAME, 'readwrite');
      tx.objectStore(STORE_NAME).put(record);
      tx.oncomplete = function () { resolve(true); };
      tx.onerror = function () { reject(tx.error || new Error('Could not save the offline snapshot.')); };
      tx.onabort = function () { reject(tx.error || new Error('Offline snapshot write was aborted.')); };
    });
  }
  async function readLocalSnapshot(userId) {
    if (!userId) return null;
    restoreCloudBaseline(userId);
    if (companion.cachedSnapshot && companion.cachedSnapshot.userId === userId) {
      return Object.assign({}, companion.cachedSnapshot, {
        pendingSync: !!companion.cachedSnapshot.pendingSync || queueMarkerExists(userId)
      });
    }
    try {
      const record = await readIdbRecord(userId);
      restoreCloudBaseline(userId, record);
      if (record && record.userId === userId && typeof record.stateJson === 'string') {
        const state = JSON.parse(record.stateJson);
        return {
          userId: userId, state: state,
          pendingSync: !!record.pendingSync || queueMarkerExists(userId),
          savedAt: Number(record.savedAt) || Number(state.savedAt) || 0,
          source: 'indexeddb', reason: String(record.reason || '')
        };
      }
    } catch (error) {
      console.warn('MediaFlow Companion: IndexedDB read unavailable; checking account cache.', error);
    }
    try {
      const cache = await originalReadRecoveryCache();
      if (cache && cache.source === 'account' && cache.state &&
          String(cache.state.userId || userId) === userId) {
        restoreCloudBaseline(userId);
        return {
          userId: userId, state: cache.state,
          pendingSync: queueMarkerExists(userId),
          savedAt: Number(cache.cachedAt) || Number(cache.state.savedAt) || 0,
          source: 'local-cache'
        };
      }
    } catch (_) {}
    return null;
  }
  async function saveLocalSnapshot(userId, state, pending, reason, serialized) {
    if (!userId || !state || typeof state !== 'object') {
      throw new Error('The local snapshot has no verified account or state.');
    }
    const json = typeof serialized === 'string' ? serialized : JSON.stringify(state);
    const record = {
      userId: userId, stateJson: json, pendingSync: !!pending,
      savedAt: Number(state.savedAt) || Date.now(),
      baseUpdatedAt: companion.lastCloudUpdatedAt,
      baseProjection: companion.lastCloudProjection,
      storedAt: Date.now(), reason: String(reason || '').slice(0, 160)
    };
    let indexedDbSaved = false;
    try { await writeIdbRecord(record); indexedDbSaved = true; }
    catch (error) { console.warn('MediaFlow Companion: IndexedDB save failed.', error); }
    let cacheSaved = false;
    if (!indexedDbSaved) {
      try { cacheSaved = originalWriteRecoveryCache(state, json) === true; } catch (_) {}
    }
    if (!indexedDbSaved && !cacheSaved) {
      throw new Error('Could not save a local offline copy. Free device storage and try again.');
    }
    if (pending) markPending(userId, reason);
    else clearPendingMarker(userId);
    companion.pending = !!pending;
    companion.cachedSnapshot = {
      userId: userId, state: state, pendingSync: !!pending,
      savedAt: Number(record.savedAt) || Date.now(),
      source: indexedDbSaved ? 'indexeddb' : 'local-cache',
      reason: String(reason || '')
    };
    updateStatus();
    return true;
  }
  function stateWithoutDraft(state) {
    const copy = Object.assign({}, state && typeof state === 'object' ? state : {});
    delete copy[DRAFT_FIELD];
    return copy;
  }
  function attachLocalDraft(state, userId) {
    const copy = Object.assign({}, state && typeof state === 'object' ? state : {});
    const draft = readLocalDraft(userId);
    if (draft && draftIsEligible(draft)) copy[DRAFT_FIELD] = cloudDraftCopy(draft);
    return copy;
  }
  function mergeStateAndDraft(localState, remoteState, userId, remoteUpdatedAt) {
    const localCore = stateWithoutDraft(localState);
    const remoteCore = stateWithoutDraft(remoteState);
    const versionChanged = !!(companion.lastCloudUpdatedAt && remoteUpdatedAt &&
      remoteUpdatedAt !== companion.lastCloudUpdatedAt);
    const base = companion.lastCloudProjection || null;
    let coreResult;
    if (versionChanged && base) {
      coreResult = mergeConcurrentStates(localCore, remoteCore, base,
        companion.conflictResolution && companion.conflictResolution.strategy);
      if (coreResult.conflicts.length) {
        companion.stateConflict = {
          paths: coreResult.conflicts.slice(),
          localState: cloneJson(localCore),
          remoteState: cloneJson(remoteCore)
        };
        throw new Error('Cloud and phone changed the same account fields. '
          + 'Both copies are safe; choose which conflicting values to keep before syncing.');
      }
    } else {
      coreResult = { state: mergeOfflineStates(localCore, remoteCore), conflicts: [] };
    }

    const localDraft = readLocalDraft(userId) ||
      (localState && localState[DRAFT_FIELD]);
    const remoteDraft = remoteState && remoteState[DRAFT_FIELD];
    let chosenDraft = remoteDraft;
    let draftToMarkSynced = null;
    if (localDraft && localDraft.userId === userId && draftIsEligible(localDraft)) {
      const localDirty = Number(localDraft.savedAt) > Number(localDraft.cloudSyncedAt || 0);
      const localTime = Number(localDraft.savedAt) || 0;
      const remoteTime = Number(remoteDraft && remoteDraft.savedAt) || 0;
      if (localDirty && remoteDraft && remoteDraft.userId === userId && remoteTime > localTime) {
        companion.draftConflict = true;
        companion.conflictingCloudDraft = cloudDraftCopy(remoteDraft);
        chosenDraft = remoteDraft;
      } else if (localDirty || !remoteDraft || localTime > remoteTime) {
        chosenDraft = cloudDraftCopy(localDraft);
        draftToMarkSynced = localDraft;
      } else if (remoteDraft && remoteTime === localTime &&
          draftContentKey(localDraft) !== draftContentKey(remoteDraft)) {
        companion.draftConflict = true;
        companion.conflictingCloudDraft = cloudDraftCopy(remoteDraft);
        chosenDraft = remoteDraft;
      } else {
        chosenDraft = remoteDraft;
        if (remoteDraft) captureCloudDraft(remoteState, userId);
      }
    }
    if (chosenDraft) coreResult.state[DRAFT_FIELD] = cloudDraftCopy(chosenDraft);
    return {
      state: coreResult.state,
      draftToMarkSynced: draftToMarkSynced,
      remoteChanged: versionChanged
    };
  }

  async function uploadSnapshot(userId, state, serialized, allowCreate) {
    if (!supabase || !userId || String(AUTH_USER && AUTH_USER.id || '') !== userId) {
      throw new Error('The saved account is not ready to sync.');
    }
    const assertUploadAccount = function () {
      if (String(AUTH_USER && AUTH_USER.id || '') !== userId || uid() !== userId) {
        throw new Error('MediaFlow account changed during sync. The other account was not modified.');
      }
    };
    const candidate = Object.assign({}, state || {});
    const localDraft = readLocalDraft(userId);
    if (localDraft && draftIsEligible(localDraft)) candidate[DRAFT_FIELD] = cloudDraftCopy(localDraft);
    let lastError = null;
    let sawRemoteChange = false;
    for (let attempt = 0; attempt < 4; attempt++) {
      assertUploadAccount();
      const remote = await originalFetchCloudState();
      assertUploadAccount();
      if (!remote || !remote.found || !remote.state) {
        if (!allowCreate) {
          throw new Error('The existing MediaFlow cloud row could not be confirmed. '
            + 'Your local copy is safe; no row was created or overwritten.');
        }
        const prepared = mergeStateAndDraft(candidate, {}, userId, null);
        try {
          const inserted = await window.MFAndroidCloudCAS.insertIfAbsent(
            supabase, userId, prepared.state, encodeCloudState, assertUploadAccount);
          if (inserted.written) {
            setCloudBaseline(userId, prepared.state, inserted.updatedAt);
            if (prepared.draftToMarkSynced) markLocalDraftSynced(userId, prepared.draftToMarkSynced);
            companion.stateConflict = null;
            companion.conflictResolution = null;
            return { state: prepared.state, updatedAt: inserted.updatedAt,
              attempts: attempt + 1, remoteChanged: false };
          }
        } catch (error) {
          if (String(error && error.code || '') !== '23505') throw error;
          lastError = error;
        }
        await new Promise(resolve => setTimeout(resolve, 80 * (attempt + 1)));
        continue;
      }
      if (typeof remote.updatedAt !== 'string' || !remote.updatedAt) {
        throw new Error('MediaFlow cloud version is missing. Refusing an unconditional write.');
      }
      if (companion.lastCloudUpdatedAt && remote.updatedAt !== companion.lastCloudUpdatedAt) {
        sawRemoteChange = true;
      }
      captureCloudDraft(remote.state, userId);
      const prepared = mergeStateAndDraft(candidate, remote.state, userId, remote.updatedAt);
      const result = await window.MFAndroidCloudCAS.update(
        supabase, userId, remote.updatedAt, prepared.state, encodeCloudState, assertUploadAccount);
      if (result.written) {
        setCloudBaseline(userId, prepared.state, result.updatedAt);
        if (prepared.draftToMarkSynced) markLocalDraftSynced(userId, prepared.draftToMarkSynced);
        companion.stateConflict = null;
        companion.conflictResolution = null;
        return {
          state: prepared.state,
          updatedAt: result.updatedAt,
          attempts: attempt + 1,
          remoteChanged: sawRemoteChange || prepared.remoteChanged
        };
      }
      lastError = new Error('Cloud state changed during the update; retrying with a fresh version.');
      await new Promise(resolve => setTimeout(resolve, 80 * (attempt + 1)));
    }
    throw lastError || new Error('Cloud changed repeatedly. Local changes remain queued for a safe retry.');
  }
  function mergeOfflineStates(localState, remoteState) {
    const localTime = Number(localState && localState.savedAt) || 0;
    const remoteTime = Number(remoteState && remoteState.savedAt) || 0;
    const primary = localTime >= remoteTime ? localState : remoteState;
    const secondary = primary === localState ? remoteState : localState;
    const merged = mergeStates(primary, secondary);
    const unique = new Map();
    const rows = []
      .concat(Array.isArray(remoteState && remoteState.completionTimeline) ? remoteState.completionTimeline : [])
      .concat(Array.isArray(localState && localState.completionTimeline) ? localState.completionTimeline : []);
    rows.forEach(function (row) {
      if (!row || typeof row !== 'object') return;
      const key = String(row.libraryId || '') + '::' + String(row.completedAt || '') + '::' + String(row.title || '');
      unique.set(key, row);
    });
    merged.completionTimeline = Array.from(unique.values());
    merged.migrations = Object.assign({}, secondary && secondary.migrations || {}, primary && primary.migrations || {});
    // A merge is not a user edit; preserve meaningful source timestamps.
    merged.savedAt = Math.max(localTime, remoteTime);
    return merged;
  }
  function updateStatus() {
    let button = document.getElementById('mf-android-companion-status');
    if (!button && document.body) {
      button = document.createElement('button');
      button.type = 'button';
      button.id = 'mf-android-companion-status';
      button.className = 'mf-android-companion-status';
      button.setAttribute('aria-live', 'polite');
      button.setAttribute('aria-label', 'Account sync status. Tap to sync.');
      button.addEventListener('click', function () { reconcile(true); });
      document.body.appendChild(button);
    }
    if (!button) return;
    if (!uid() || !companion.booted) {
      button.hidden = true;
      return;
    }
    button.hidden = false;
    let state = 'synced';
    let message = 'Synced with Supabase';
    if (companion.syncing) {
      state = 'syncing'; message = 'Syncing with Supabase…';
    } else if (!navigator.onLine || companion.active) {
      state = 'offline';
      message = companion.pending ? 'Offline · changes saved on phone' : 'Offline · account available';
    } else if (companion.needsAuth) {
      state = 'attention'; message = 'Saved on phone · sign in to sync';
    } else if (companion.attention) {
      state = 'attention'; message = 'Saved locally · sync needs attention';
    } else if (companion.pending) {
      state = 'pending'; message = 'Changes waiting to sync';
    }
    button.dataset.state = state;
    button.textContent = message;
    button.title = 'Tap to sync now. Offline drafts and logs stay on this phone until they can be uploaded.';
  }
  function saveDraftNow() {
    const userId = uid();
    if (!userId || typeof S === 'undefined') return false;
    try {
      const payload = {
        version: 1, userId: userId, savedAt: Date.now(),
        view: ['dashboard', 'library', 'history'].includes(String(S.view)) ? String(S.view) : 'dashboard',
        logging: !!S.logging, logMode: companion.logMode === 'batch' ? 'batch' : 'single',
        singleDraftExists: !!(companion.hasSingleDraft || (S.logging && companion.logMode === 'single') ||
          (S.logDraft && (S.logDraft.categoryId || (S.logDraft.entries || []).length))),
        logDraft: S.logDraft && typeof S.logDraft === 'object' ? S.logDraft : {},
        entryDraft: S.entryDraft && typeof S.entryDraft === 'object' ? S.entryDraft : { title: '', qty: 1 },
        batchDraftExists: !!(companion.hasBatchDraft || (S.batchDraft && Array.isArray(S.batchDraft.rows) && S.batchDraft.rows.length)),
        batchDraft: S.batchDraft && typeof S.batchDraft === 'object' ? S.batchDraft : { rows: [], note: '', date: '' }
      };
      localStorage.setItem(draftKey(userId), JSON.stringify(payload));
      companion.hasSingleDraft = payload.singleDraftExists;
      companion.hasBatchDraft = payload.batchDraftExists;
      return true;
    } catch (error) {
      console.warn('MediaFlow Companion: draft could not be saved locally.', error);
      return false;
    }
  }
  function scheduleDraftSave() {
    if (draftTimer !== null) clearTimeout(draftTimer);
    draftTimer = setTimeout(function () { draftTimer = null; saveDraftNow(); }, 180);
  }
  function restoreDraft() {
    const userId = uid();
    if (!userId) return false;
    try {
      const payload = JSON.parse(localStorage.getItem(draftKey(userId)) || 'null');
      if (!payload || payload.version !== 1 || payload.userId !== userId ||
          Date.now() - (Number(payload.savedAt) || 0) > 90 * 24 * 60 * 60 * 1000) return false;
      if (payload.singleDraftExists && payload.logDraft && typeof payload.logDraft === 'object') {
        S.logDraft = payload.logDraft;
        if (payload.entryDraft && typeof payload.entryDraft === 'object') S.entryDraft = payload.entryDraft;
        companion.hasSingleDraft = true;
      } else {
        companion.hasSingleDraft = false;
      }
      ensureDraftTask();
      if (payload.batchDraftExists && payload.batchDraft && typeof payload.batchDraft === 'object') {
        S.batchDraft = payload.batchDraft;
        companion.hasBatchDraft = true;
      } else {
        companion.hasBatchDraft = false;
      }
      companion.logMode = payload.logMode === 'batch' ? 'batch' : 'single';
      S.view = ['dashboard', 'library', 'history'].includes(String(payload.view)) ? String(payload.view) : 'dashboard';
      S.logging = !!payload.logging && (companion.logMode === 'batch' ? companion.hasBatchDraft : companion.hasSingleDraft);
      if (S.logging && companion.hasSingleDraft && S.logDraft && S.logDraft.categoryId && S.currentTask) S.sessionActive = true;
      return true;
    } catch (error) {
      console.warn('MediaFlow Companion: could not restore saved draft.', error);
      return false;
    }
  }
  function navigate(target) {
    if (target === 'log') return openLogging();
    if (target === 'batch') return openBatchLogging();
    saveDraftNow();
    S.logging = false;
    companion.logMode = 'single';
    if (target === 'library') App.setView('library');
    else if (target === 'history') App.setView('history');
    else App.setView('dashboard');
    scheduleDraftSave();
  }
  function ensureDraftTask() {
    if (S.currentTask) return true;
    if (!companion.hasSingleDraft || !S.logDraft || !S.logDraft.categoryId) return false;
    const category = getCategory(S.logDraft.categoryId);
    if (!category) return false;
    const amount = Math.max(1, Number(S.logDraft.amount) || 1);
    S.currentTask = {
      categoryId: category.id, unit: category.unit, low: amount, high: amount,
      targetMid: amount, targetAmount: amount, title: '', libraryId: null,
      reasons: [], offlineDraftResume: true, createdAt: Date.now()
    };
    S.sessionActive = true;
    return true;
  }
  function openLogging() {
    saveDraftNow();
    S.view = 'dashboard';
    companion.logMode = 'single';
    ensureDraftTask();
    if (!S.sessionActive || !S.currentTask) App.startSession();
    if (companion.hasSingleDraft && S.logDraft && S.logDraft.categoryId) {
      S.logging = true;
      render();
    } else {
      App.openLogForm();
    }
    scheduleDraftSave();
  }
  function openBatchLogging() {
    saveDraftNow();
    S.view = 'dashboard';
    S.logging = true;
    companion.logMode = 'batch';
    if (typeof ensureBatchDraft === 'function') ensureBatchDraft();
    companion.hasBatchDraft = !!(companion.hasBatchDraft ||
      (S.batchDraft && Array.isArray(S.batchDraft.rows) && S.batchDraft.rows.length));
    render();
    scheduleDraftSave();
  }
  function toggleExactTitleRecommendations(enabled) {
    const on = !!enabled;
    S.settings = S.settings || {};
    S.settings.exactTitleRecommendations = on;
    if (on && S.currentTask && !S.currentTask.title && typeof v180RecommendationCandidates === 'function') {
      const candidate = v180RecommendationCandidates(S.currentTask)[0];
      if (candidate) {
        S.currentTask.libraryId = candidate.id;
        S.currentTask.title = cleanTitle(candidate.title);
        S.currentTask.v180RecommendationHistory = [];
        S.currentTask.v180TitleRerolls = 0;
        if (typeof v180EnsureRecommendationHistory === 'function') v180EnsureRecommendationHistory(S.currentTask);
      }
    } else if (on && S.currentTask && typeof v180EnsureRecommendationHistory === 'function') {
      v180EnsureRecommendationHistory(S.currentTask);
    }
    persistSettings();
    persistTask();
    render();
    scheduleDraftSave();
  }
  function focusedDashboard() {
    const header = '<div class="view-head mf-android-companion-head"><div><div class="view-title">Recommendations</div><div class="view-desc">Your rotation, title picks, and logging in one place.</div></div>' +
      '<button type="button" class="btn btn-sm" onclick="window.MFAndroidCompanion.openBatchLogging()">Batch log</button></div>';
    if (S.logging && companion.logMode === 'batch') {
      return '<div class="mf-android-log-switch"><button type="button" class="btn" onclick="window.MFAndroidCompanion.openLogging()">Single log</button><button type="button" class="btn btn-primary" aria-pressed="true">Batch log</button></div>' +
        renderBatchLog();
    }
    if ((!S.sessionActive || !S.currentTask) && !S.logging) {
      return header + '<section class="hero mf-android-companion-hero"><div class="hero-eyebrow">MediaFlow recommends</div>' +
        '<div class="hero-name">Ready for your next pick?</div><div class="hero-amount">Start a recommendation session. Your category rotation and personal data come from your existing MediaFlow account.</div>' +
        '<div class="hero-actions"><button type="button" class="btn btn-primary" onclick="App.startSession()">Get recommendations</button>' +
        '<button type="button" class="btn" onclick="window.MFAndroidCompanion.openLogging()">Log consumption</button>' +
        '<button type="button" class="btn btn-ghost" onclick="window.MFAndroidCompanion.openBatchLogging()">Batch log</button></div></section>';
    }
    if (!S.currentTask) {
      return header + '<section class="card"><p>The saved logging draft needs its original category. Start a recommendation session or open the Library workspace to continue.</p>' +
        '<button type="button" class="btn btn-primary" onclick="App.startSession()">Get recommendations</button></section>';
    }
    const task = S.currentTask;
    const cat = getCategory(task.categoryId);
    if (!cat) {
      return header + '<section class="card"><p>The saved recommendation category is unavailable. Your data is preserved.</p><button type="button" class="btn btn-primary" onclick="App.startSession()">Get another recommendation</button></section>';
    }
    const amount = task.low === task.high ? String(task.low) + ' ' + unitLabel(task.unit, task.low) :
      String(task.low) + '–' + String(task.high) + ' ' + unitLabel(task.unit, task.high);
    const exactOn = !!(S.settings && S.settings.exactTitleRecommendations);
    const titleMode = '<section class="card mf-android-title-mode"><label><input type="checkbox" ' +
      (exactOn ? 'checked' : '') + ' onchange="window.MFAndroidCompanion.toggleExactTitleRecommendations(this.checked)">' +
      '<span><b>Exact-title recommendations</b><small>Enable title rerolls and reroll history. This preference syncs with your MediaFlow account.</small></span></label></section>';
    let titleHtml = mf395DashboardRecommendationHtml(task, cat);
    if (exactOn && !task.title) {
      titleHtml += '<div class="mf-android-title-empty"><button type="button" class="btn" onclick="App.v180RerollRecommendedTitle()">Choose a recommended title</button></div>';
    }
    const controls = S.logging
      ? '<div class="mf-android-log-switch"><button type="button" class="btn btn-primary" aria-pressed="true">Single log</button><button type="button" class="btn" onclick="window.MFAndroidCompanion.openBatchLogging()">Batch log</button></div>' +
        renderLogForm(task, cat)
      : '<div class="hero-actions"><button type="button" class="btn btn-primary" onclick="App.openLogForm()">Log &amp; complete</button>' +
        '<button type="button" class="btn" onclick="App.rotateTask()">Reroll recommendation</button>' +
        '<button type="button" class="btn btn-ghost" onclick="App.skipTask()">Skip</button>' +
        '<button type="button" class="btn btn-ghost" onclick="App.endSession()">End session</button></div>' +
        '<button type="button" class="link-btn" style="margin-top:12px" onclick="App.toggleReasonDetail()">' +
        (S.showReasonDetail ? 'Hide' : 'Why this pick?') + '</button>' +
        (S.showReasonDetail ? renderReasonDetail(cat) : '');
    return header + titleMode + '<section class="hero mf-android-companion-hero"><div class="hero-eyebrow">Next recommendation</div>' +
      '<div class="hero-cat"><div class="hero-icon" style="background:' + escapeHtml(cat.color) + '22;color:' + escapeHtml(cat.color) + '">' +
      v144CategoryIconHtml(cat) + '</div><div><div class="hero-name">' + escapeHtml(cat.name) + '</div></div></div>' +
      '<div class="hero-amount">Consume <b>' + escapeHtml(amount) + '</b></div>' + titleHtml + controls + '</section>';
  }

  async function reconcile(force) {
    if (companion.syncing) return false;
    const userId = uid();
    if (!userId || !supabase) { updateStatus(); return false; }
    if (!navigator.onLine) {
      companion.active = true; S.offlineMode = true; updateStatus(); return false;
    }
    companion.syncing = true;
    companion.needsAuth = false;
    updateStatus();
    try {
      let authResult = await supabase.auth.getSession();
      let session = authResult && authResult.data && authResult.data.session;
      if ((authResult && authResult.error) || !session || !session.user || session.user.id !== userId) {
        authResult = await supabase.auth.refreshSession();
        if (authResult && authResult.error) throw authResult.error;
        session = authResult && authResult.data && authResult.data.session;
      }
      if (!session || !session.user || session.user.id !== userId) {
        companion.needsAuth = true;
        throw new Error('The saved session needs to reconnect before cloud sync can continue.');
      }
      AUTH_USER = session.user;
      const local = await readLocalSnapshot(userId);
      const queued = !!(local && local.pendingSync) || queueMarkerExists(userId);
      const remote = await originalFetchCloudState();
      const pending = queued || !!(local && local.state &&
        (Number(local.state.savedAt) || 0) > (Number(remote && remote.state && remote.state.savedAt) || 0) + 1000);
      if (!remote || !remote.found || !remote.state) {
        if (pending || local && local.state) {
          companion.attention = true;
          throw new Error('The cloud state is missing. Your local copy is safe; no automatic overwrite was attempted.');
        }
        companion.active = false; companion.pending = false; companion.attention = false; S.offlineMode = false; window.__mfAndroidOfflineMode = false;
        updateStatus();
        return true;
      }
      let state = remote.state;
      if (pending && local && local.state) state = mergeOfflineStates(local.state, remote.state);
      if (pending) {
        const json = JSON.stringify(state);
        await saveLocalSnapshot(userId, state, true, 'syncing offline changes', json);
        await uploadSnapshot(userId, state, json);
      }
      await saveLocalSnapshot(userId, state, false, 'synced with Supabase');
      companion.active = false; companion.pending = false; companion.needsAuth = false; companion.attention = false; S.offlineMode = false; window.__mfAndroidOfflineMode = false;
      if (typeof v115StartWithData === 'function') await v115StartWithData(state);
      updateStatus();
      return true;
    } catch (error) {
      companion.active = isNetworkError(error) || navigator.onLine === false;
      S.offlineMode = true;
      companion.pending = companion.pending || queueMarkerExists(userId);
      companion.needsAuth = requiresReauthentication(error);
      companion.attention = !companion.needsAuth && !isNetworkError(error);
      console.warn('MediaFlow Companion: sync deferred; local data remains saved.', error);
      updateStatus();
      return false;
    } finally {
      companion.syncing = false;
      updateStatus();
    }
  }

  /* IndexedDB is the large-state source of truth on Android. Avoid synchronous
     multi-megabyte localStorage writes on every save; keep the old recovery cache
     as a fallback only when IndexedDB cannot store the state. */
  v115ReadRecoveryCache = async function () {
    const userId = uid();
    if (userId && companion.cachedSnapshot && companion.cachedSnapshot.userId === userId) {
      return { state: companion.cachedSnapshot.state, source: 'account', cachedAt: companion.cachedSnapshot.savedAt };
    }
    if (userId) {
      try {
        const record = await readIdbRecord(userId);
        if (record && record.userId === userId && typeof record.stateJson === 'string') {
          const state = JSON.parse(record.stateJson);
          companion.cachedSnapshot = {
            userId: userId, state: state,
            pendingSync: !!record.pendingSync || queueMarkerExists(userId),
            savedAt: Number(record.savedAt) || Number(state.savedAt) || 0,
            source: 'indexeddb', reason: String(record.reason || '')
          };
          return { state: state, source: 'account', cachedAt: companion.cachedSnapshot.savedAt };
        }
      } catch (_) {}
    }
    const cache = await originalReadRecoveryCache.apply(this, arguments);
    if (cache && cache.source === 'account' && userId) {
      companion.cachedSnapshot = {
        userId: userId, state: cache.state, pendingSync: queueMarkerExists(userId),
        savedAt: Number(cache.cachedAt) || Number(cache.state && cache.state.savedAt) || 0,
        source: 'local-cache'
      };
      return cache;
    }
    return null;
  };
  v115WriteRecoveryCache = function (state, serializedState) {
    if (window.indexedDB && uid()) return true;
    return originalWriteRecoveryCache.apply(this, arguments);
  };

  /* The core app's own full-state save stays the single cloud format. This
     wrapper adds a local-first queue and a bounded network attempt. */
  const originalRawSet = rawSet;
  const originalFetchCloudState = v115FetchCloudState;
  async function rawSetWithOfflineQueue(key, value) {
    if (key !== STATE_KEY) return originalRawSet.apply(this, arguments);
    const userId = uid();
    if (!userId || !value || typeof value !== 'object') throw new Error('MediaFlow account is not ready for a local save.');
    const wasPending = !!companion.pending || queueMarkerExists(userId);
    let stateToQueue = attachLocalDraft(value, userId);
    let jsonToQueue = JSON.stringify(stateToQueue);
    await saveLocalSnapshot(userId, stateToQueue, true, 'save pending', jsonToQueue);
    if (!navigator.onLine || companion.active || companion.needsAuth || companion.attention) {
      if (!navigator.onLine) companion.active = true;
      companion.pending = true; S.offlineMode = true;
      updateStatus();
      return true;
    }
    try {
      if (wasPending) {
        const remote = await originalFetchCloudState();
        if (!remote || !remote.found || !remote.state) {
          throw new Error('The cloud state could not be confirmed. The local copy is queued safely.');
        }
        stateToQueue = mergeOfflineStates(value, remote.state);
        jsonToQueue = JSON.stringify(stateToQueue);
      }
      await uploadSnapshot(userId, stateToQueue, jsonToQueue);
      await saveLocalSnapshot(userId, stateToQueue, false, 'synced with Supabase', jsonToQueue);
      companion.active = false; companion.pending = false; companion.needsAuth = false; companion.attention = false; S.offlineMode = false; window.__mfAndroidOfflineMode = false;
      if (wasPending && stateToQueue !== value && typeof v115StartWithData === 'function') {
        await v115StartWithData(stateToQueue);
      }
      updateStatus();
      return true;
    } catch (error) {
      try { await saveLocalSnapshot(userId, stateToQueue, true, String(error && (error.message || error) || 'sync deferred'), jsonToQueue); }
      catch (storageError) {
        console.error('MediaFlow Companion: failed to preserve the queued state.', storageError);
        updateStatus();
        throw storageError;
      }
      companion.active = isNetworkError(error) || navigator.onLine === false; companion.pending = true; S.offlineMode = true;
      companion.needsAuth = requiresReauthentication(error);
      companion.attention = !companion.needsAuth && !isNetworkError(error);
      console.warn('MediaFlow Companion: saved locally; cloud upload queued.', error);
      updateStatus();
      return true;
    }
  }

  /* Startup: on a network failure, boot the account-scoped local snapshot.
     A missing cloud row remains a safety stop and is never auto-created. */
  v115FetchCloudState = async function () {
    const userId = uid();
    try {
      const remote = await originalFetchCloudState.apply(this, arguments);
      if (!remote || !remote.found || !remote.state) return remote;
      const local = await readLocalSnapshot(userId);
      const localIsNewer = !!(local && local.state &&
        (Number(local.state.savedAt) || 0) > (Number(remote.state.savedAt) || 0) + 1000);
      if (local && local.state && (local.pendingSync || localIsNewer)) {
        const merged = mergeOfflineStates(local.state, remote.state);
        const json = JSON.stringify(merged);
        try {
          await saveLocalSnapshot(userId, merged, true, 'syncing offline changes', json);
          await uploadSnapshot(userId, merged, json);
          await saveLocalSnapshot(userId, merged, false, 'synced with Supabase', json);
          companion.active = false; companion.pending = false; companion.needsAuth = false; companion.attention = false; S.offlineMode = false; window.__mfAndroidOfflineMode = false;
          return Object.assign({}, remote, { state: merged });
        } catch (error) {
          await saveLocalSnapshot(userId, merged, true, String(error && (error.message || error) || 'sync deferred'), json);
          companion.active = isNetworkError(error) || navigator.onLine === false; companion.pending = true; S.offlineMode = true;
          companion.needsAuth = requiresReauthentication(error);
          companion.attention = !companion.needsAuth && !isNetworkError(error);
          updateStatus();
          return { found: true, state: merged, updatedAt: null, offline: true };
        }
      }
      await saveLocalSnapshot(userId, remote.state, false, 'synced with Supabase');
      companion.active = false; companion.pending = false; companion.needsAuth = false; companion.attention = false; S.offlineMode = false; window.__mfAndroidOfflineMode = false;
      return remote;
    } catch (error) {
      const local = await readLocalSnapshot(userId);
      if (local && local.state && (navigator.onLine === false || isNetworkError(error))) {
        try {
          await saveLocalSnapshot(userId, local.state, !!local.pendingSync, 'restored local account snapshot');
        } catch (storageError) {
          console.warn('MediaFlow Companion: could not seed IndexedDB from the previous local cache.', storageError);
        }
        companion.active = true; companion.pending = !!local.pendingSync; S.offlineMode = true;
        companion.needsAuth = false; companion.attention = false;
        if (local.pendingSync) markPending(userId, 'waiting for network');
        updateStatus();
        return { found: true, state: local.state, updatedAt: null, offline: true };
      }
      throw error;
    }
  };

  const originalStartWithData = v115StartWithData;
  v115StartWithData = async function (data) {
    const result = await originalStartWithData.apply(this, arguments);
    if (result) {
      companion.booted = true;
      restoreDraft();
      render();
      updateStatus();
      if (navigator.onLine && (companion.active || companion.pending)) {
        setTimeout(function () { reconcile(false); }, 500);
      }
    }
    return result;
  };
  rawSet = rawSetWithOfflineQueue;

  /* Keep only the mobile companion surfaces. The full v553 recommendation,
     Library, History, XP, and logging functions remain the original functions. */
  NAV_ITEMS.splice(0, NAV_ITEMS.length,
    { id: 'dashboard', label: 'Recommendations' },
    { id: 'library', label: 'Library workspace' },
    { id: 'history', label: 'Log history' }
  );
  MOBILE_PRIMARY_NAV.splice(0, MOBILE_PRIMARY_NAV.length, 'dashboard', 'library', 'history');
  MOBILE_MORE_NAV.splice(0, MOBILE_MORE_NAV.length);
  v161VisibleNavItems = function () { return NAV_ITEMS.slice(); };
  renderMobileTabs = function () {
    const logIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 5H5v16h14V5h-3"/><path d="M9 3h6v4H9z"/><path d="m8 13 2 2 5-5"/></svg>';
    function tab(id, label, icon, active) {
      return '<button type="button" class="mtab ' + (active ? 'active' : '') +
        '" onclick="window.MFAndroidCompanion.navigate(&quot;' + id + '&quot;)" aria-label="' + label + '">' +
        icon + '<span>' + label + '</span></button>';
    }
    return tab('dashboard', 'Recommend', ICONS.dashboard, S.view === 'dashboard' && !S.logging) +
      tab('log', 'Log', logIcon, S.view === 'dashboard' && !!S.logging) +
      tab('library', 'Library', ICONS.library, S.view === 'library') +
      tab('history', 'History', ICONS.history, S.view === 'history');
  };
  renderDashboard = focusedDashboard;

  const originalSetView = App.setView;
  App.setView = function (view) {
    const target = ['dashboard', 'library', 'history'].includes(String(view)) ? String(view) : 'dashboard';
    if (S.logging) saveDraftNow();
    S.logging = false;
    companion.logMode = 'single';
    const result = originalSetView.call(this, target);
    scheduleDraftSave();
    return result;
  };
  const originalOpenLogForm = App.openLogForm;
  if (typeof originalOpenLogForm === 'function') {
    App.openLogForm = function () {
      companion.logMode = 'single';
      companion.hasSingleDraft = true;
      const result = originalOpenLogForm.apply(this, arguments);
      scheduleDraftSave();
      return result;
    };
  }
  const originalCancelLogForm = App.cancelLogForm;
  if (typeof originalCancelLogForm === 'function') {
    App.cancelLogForm = function () {
      const result = originalCancelLogForm.apply(this, arguments);
      companion.hasSingleDraft = false;
      S.logDraft = {};
      S.entryDraft = { title: '', qty: 1 };
      scheduleDraftSave();
      return result;
    };
  }
  const originalSubmitLog = App.submitLog;
  if (typeof originalSubmitLog === 'function') {
    App.submitLog = function () {
      const before = (S.sessions || []).length;
      const result = originalSubmitLog.apply(this, arguments);
      if ((S.sessions || []).length > before) {
        companion.hasSingleDraft = false;
        S.logDraft = {};
        S.entryDraft = { title: '', qty: 1 };
        saveDraftNow();
      } else scheduleDraftSave();
      return result;
    };
  }
  const originalSubmitBatch = App.submitBatchLog;
  if (typeof originalSubmitBatch === 'function') {
    App.submitBatchLog = function () {
      const before = (S.sessions || []).length;
      const result = originalSubmitBatch.apply(this, arguments);
      if ((S.sessions || []).length > before && S.view === 'history') {
        companion.hasBatchDraft = false;
        S.logging = false;
        companion.logMode = 'single';
        S.batchDraft = { rows: [], note: '', date: typeof todayISO === 'function' ? todayISO() : '' };
        saveDraftNow();
      } else scheduleDraftSave();
      return result;
    };
  }
  const originalClearBatch = App.clearBatchLog;
  if (typeof originalClearBatch === 'function') {
    App.clearBatchLog = function () {
      const result = originalClearBatch.apply(this, arguments);
      companion.hasBatchDraft = false;
      S.batchDraft = { rows: [], note: '', date: typeof todayISO === 'function' ? todayISO() : '' };
      scheduleDraftSave();
      return result;
    };
  }

  const originalRender = render;
  render = function () {
    const result = originalRender.apply(this, arguments);
    scheduleDraftSave();
    updateStatus();
    return result;
  };
  function mountBackupTools() {
    const root = document.getElementById('view-root');
    if (!root) return;
    const existing = document.getElementById('mf-android-backup-tools');
    if (String(S.view) !== 'library') {
      if (existing) existing.remove();
      return;
    }
    if (existing) return;
    const head = root.querySelector('.view-head');
    if (!head) return;
    const card = document.createElement('section');
    card.id = 'mf-android-backup-tools';
    card.className = 'card mf-android-backup-tools';
    const heading = document.createElement('div');
    heading.className = 'mf-android-backup-heading';
    heading.textContent = 'Automatic backups';
    const description = document.createElement('p');
    description.textContent = 'Choose a folder on this phone, create a backup now, or enable scheduled backups. These controls use MediaFlow’s existing full JSON backup.';
    const actions = document.createElement('div');
    actions.className = 'mf-android-backup-actions';
    function makeButton(label, handler, active) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = active ? 'btn btn-primary' : 'btn';
      button.textContent = label;
      button.onclick = handler;
      return button;
    }
    actions.appendChild(makeButton('Choose backup folder', function () {
      if (typeof App.chooseBackupFolder === 'function') App.chooseBackupFolder();
    }, false));
    actions.appendChild(makeButton('Back up now', function () {
      if (typeof App.backupNow === 'function') App.backupNow();
    }, false));
    const enabled = !!(S.settings && S.settings.backup && S.settings.backup.enabled);
    actions.appendChild(makeButton('Automatic backups: ' + (enabled ? 'On' : 'Off'), function () {
      if (typeof App.updateBackup === 'function') App.updateBackup('enabled', !(
        S.settings && S.settings.backup && S.settings.backup.enabled
      ));
    }, enabled));
    card.append(heading, description, actions);
    head.insertAdjacentElement('afterend', card);
  }

  function initializeCompanion() {
    updateStatus();
    mountBackupTools();
    const root = document.getElementById('view-root');
    if (root && !observer) {
      observer = new MutationObserver(function () {
        scheduleDraftSave();
        updateStatus();
        mountBackupTools();
      });
      observer.observe(root, { childList: true, subtree: true });
    }
    document.addEventListener('input', function (event) {
      if (event.target && event.target.closest && event.target.closest('#view-root')) scheduleDraftSave();
    }, true);
    document.addEventListener('change', function (event) {
      if (event.target && event.target.closest && event.target.closest('#view-root')) scheduleDraftSave();
    }, true);
    window.addEventListener('pagehide', saveDraftNow);
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'hidden') saveDraftNow();
      else if (navigator.onLine && (companion.active || companion.pending)) reconcile(false);
    });
    window.addEventListener('offline', function () {
      companion.active = true; S.offlineMode = true; updateStatus();
    });
    window.addEventListener('online', function () {
      companion.active = true; S.offlineMode = true; updateStatus();
      setTimeout(function () { reconcile(false); }, 400);
    });
    setInterval(function () {
      if (navigator.onLine && (companion.active || (companion.pending && !companion.needsAuth && !companion.attention))) reconcile(false);
    }, 30000);
    updateStatus();
    mountBackupTools();
  }
  const originalAuthHandler = v475HandleAuthEvent;
  v475HandleAuthEvent = function (event, session) {
    if (event === 'SIGNED_OUT' && companion.active && uid() && !V475_AUTH.logoutRequested) {
      updateStatus();
      return;
    }
    return originalAuthHandler.apply(this, arguments);
  };
  initializeCompanion();
  if (typeof window.__mfAndroidCompanionResolve === 'function') {
    const resolve = window.__mfAndroidCompanionResolve;
    window.__mfAndroidCompanionResolve = null;
    resolve(true);
  }
})();