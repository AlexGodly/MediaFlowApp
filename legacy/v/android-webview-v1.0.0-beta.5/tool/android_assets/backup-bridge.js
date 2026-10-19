/* MediaFlow Android Storage Access Framework backup protocol.
   Loaded BEFORE the v507 application bundle; contains no Supabase writes. */
(function () {
  'use strict';
  const native = window.MediaFlowNativeBackup;
  if (!native || typeof native.postMessage !== 'function') return;
  const pending = new Map();
  let sequence = 0;
  let writing = false;
  const utf8 = new TextEncoder();

  native.onmessage = function (event) {
    try {
      const data = JSON.parse(event.data);
      const item = pending.get(data.id);
      if (!item) return;
      pending.delete(data.id);
      clearTimeout(item.timeout);
      if (data.ok) item.resolve(data.result || {});
      else {
        const error = new Error(data.error || 'Android backup request failed');
        error.code = data.code || 'error';
        item.reject(error);
      }
    } catch (error) { console.error('MediaFlow Android backup response', error); }
  };

  function request(kind, options, timeoutMs) {
    return new Promise((resolve, reject) => {
      const id = ++sequence;
      const timeout = setTimeout(() => {
        pending.delete(id);
        reject(new Error('Android backup operation timed out'));
      }, timeoutMs || 30000);
      pending.set(id, {resolve, reject, timeout});
      try { native.postMessage(JSON.stringify(Object.assign({kind, id}, options || {}))); }
      catch (error) { clearTimeout(timeout); pending.delete(id); reject(error); }
    });
  }

  async function save(name, json) {
    if (writing) throw new Error('A MediaFlow backup is already in progress');
    writing = true;
    let token = null;
    try {
      const started = await request('begin', {name}, 30000);
      token = started.token;
      if (!token) throw new Error('Android did not open the backup file');
      let sent = 0;
      for (let i = 0; i < json.length;) {
        let end = Math.min(json.length, i + 32768);
        // Do not split UTF-16 surrogate pairs between UTF-8 chunks.
        if (end < json.length) {
          const code = json.charCodeAt(end - 1);
          if (code >= 0xD800 && code <= 0xDBFF) ++end;
        }
        const bytes = utf8.encode(json.slice(i, end));
        const binary = String.fromCharCode.apply(null, bytes);
        await request('chunk', {token, data: btoa(binary)}, 30000);
        sent += bytes.length;
        i = end;
      }
      return await request('finish', {token, bytes: sent}, 60000);
    } catch (error) {
      if (token) request('abort', {token}, 10000).catch(() => {});
      throw error;
    } finally { writing = false; }
  }

  window.__mfAndroidBackup = Object.freeze({
    status: () => request('status'),
    choose: () => request('choose', {}, 180000),
    save,
    isWriting: () => writing
  });
})();
