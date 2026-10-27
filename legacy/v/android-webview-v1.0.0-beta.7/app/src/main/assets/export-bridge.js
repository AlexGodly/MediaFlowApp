(async function() {
  // Executed by Android after the website initiates a blob: download.
  const url = __BLOB_URL__;
  const suggested = __SUGGESTED_NAME__;
  const bridge = window.MediaFlowNativeFiles;
  if (!bridge || !bridge.addEventListener) {
    console.error("MediaFlow Android export bridge unavailable");
    return;
  }
  const filename = (function () {
    const candidate = window.__mfAndroidDownload;
    if (candidate && candidate.url === url && Date.now() - candidate.time < 120000) {
      return candidate.name || suggested;
    }
    return suggested;
  })();
  let requestCounter = 0;
  const pending = new Map();
  function receive(event) {
    try {
      const message = JSON.parse(event.data);
      const promise = pending.get(message.id);
      if (!promise) return;
      pending.delete(message.id);
      clearTimeout(promise.timer);
      if (message.ok) promise.resolve(message);
      else promise.reject(new Error(message.error || "Native export failed"));
    } catch (e) { console.error("Invalid Android export response", e); }
  }
  bridge.addEventListener("message", receive);
  function send(kind, fields) {
    return new Promise((resolve, reject) => {
      const id = ++requestCounter;
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error("Android export timed out"));
      }, 30000);
      pending.set(id, { resolve, reject, timer });
      bridge.postMessage(JSON.stringify(Object.assign({kind, id}, fields)));
    });
  }
  let token = null;
  try {
    const blob = await (await fetch(url)).blob();
    const started = await send("start", {
      name: filename,
      mime: blob.type || "application/octet-stream",
      size: blob.size
    });
    token = started.token;
    const chunkSize = 192 * 1024;
    for (let offset = 0; offset < blob.size; offset += chunkSize) {
      const part = blob.slice(offset, Math.min(blob.size, offset + chunkSize));
      const base64 = await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onerror = () => reject(reader.error || new Error("Read failed"));
        reader.onload = () => resolve(String(reader.result).split(",")[1]);
        reader.readAsDataURL(part);
      });
      await send("chunk", { token, data: base64 });
    }
    await send("finish", { token });
  } catch (error) {
    console.error("MediaFlow Android backup export failed", error);
    if (token) { try { await send("abort", { token }); } catch (_) {} }
    window.alert("MediaFlow export failed: " + (error.message || error));
  } finally {
    bridge.removeEventListener("message", receive);
    for (const p of pending.values()) {
      clearTimeout(p.timer);
      p.reject(new Error("Export closed"));
    }
    pending.clear();
  }
})();