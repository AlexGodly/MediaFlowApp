/* Exposes only a read-only platform marker; the page gets no Node or Electron APIs. */
'use strict';
const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('MediaFlowDesktop', Object.freeze({
  platform: 'windows',
  shell: 'electron'
}));
