/* MediaFlow for Windows: hosts the packaged MediaFlow website (the same files the
   Android APK ships) in a locked-down Chromium window. No Node access for the page. */
'use strict';
const { app, BrowserWindow, Menu, net, protocol, shell } = require('electron');
const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');

const SCHEME = 'mediaflow';
const HOST = 'app';
const START_URL = `${SCHEME}://${HOST}/index.html`;

// Must run before 'ready': a standard, secure origin gives the page working
// localStorage, IndexedDB, fetch/CORS and a service worker, like the website.
protocol.registerSchemesAsPrivileged([{
  scheme: SCHEME,
  privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true,
    allowServiceWorkers: true, stream: true, codeCache: true }
}]);

const WWW = path.resolve(app.isPackaged ? path.join(process.resourcesPath, 'www') : path.join(__dirname, 'www'));

function localFileFor(requestUrl) {
  const url = new URL(requestUrl);
  if (url.host !== HOST) return null;
  let relative = decodeURIComponent(url.pathname);
  if (!relative || relative === '/') relative = '/index.html';
  const full = path.resolve(WWW, '.' + relative);
  // Never serve anything outside the packaged website folder.
  if (full !== WWW && !full.startsWith(WWW + path.sep)) return null;
  return full;
}

function isAppUrl(target) {
  try { const u = new URL(target); return u.protocol === SCHEME + ':' && u.host === HOST; }
  catch (_) { return false; }
}

function openExternally(target) {
  try {
    const u = new URL(target);
    if (u.protocol === 'https:' || u.protocol === 'http:' || u.protocol === 'mailto:') shell.openExternal(u.toString());
  } catch (_) {}
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1320,
    height: 880,
    minWidth: 380,
    minHeight: 560,
    backgroundColor: '#090c14',
    title: 'MediaFlow',
    autoHideMenuBar: true,
    show: false,
    // The packaged .exe carries the icon; this only matters when run from source.
    ...(fs.existsSync(path.join(__dirname, 'build', 'icon.png')) ? { icon: path.join(__dirname, 'build', 'icon.png') } : {}),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: true
    }
  });
  win.once('ready-to-show', () => win.show());

  // Links that leave MediaFlow (provider pages, docs) open in the default browser.
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (!isAppUrl(url)) openExternally(url);
    return { action: 'deny' };
  });
  win.webContents.on('will-navigate', (event, url) => {
    if (!isAppUrl(url)) { event.preventDefault(); openExternally(url); }
  });
  // If the page renderer crashes, reload without touching stored account data.
  win.webContents.on('render-process-gone', (_event, details) => {
    if (details.reason !== 'clean-exit') setTimeout(() => { if (!win.isDestroyed()) win.loadURL(START_URL); }, 600);
  });
  win.loadURL(START_URL);
  return win;
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    const [win] = BrowserWindow.getAllWindows();
    if (win) { if (win.isMinimized()) win.restore(); win.focus(); }
  });
  app.whenReady().then(() => {
    protocol.handle(SCHEME, (request) => {
      const file = localFileFor(request.url);
      if (!file) return new Response('Not found', { status: 404 });
      return net.fetch(pathToFileURL(file).toString());
    });
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      { label: 'MediaFlow', submenu: [{ role: 'reload' }, { role: 'forceReload' }, { type: 'separator' }, { role: 'quit' }] },
      { label: 'Edit', submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
      { label: 'View', submenu: [{ role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' }, { type: 'separator' }, { role: 'togglefullscreen' }, { role: 'toggleDevTools' }] }
    ]));
    createWindow();
    app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
  });
  app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
}
