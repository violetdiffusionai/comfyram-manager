const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('guardian', {
  getStatus: () => ipcRenderer.invoke('get-status'),
  freeVram: () => ipcRenderer.invoke('free-vram'),
  clearRam: () => ipcRenderer.invoke('clear-ram'),
  detectComfy: () => ipcRenderer.invoke('detect-comfy'),
  killAll: () => ipcRenderer.invoke('kill-all'),
  scanSecurity: () => ipcRenderer.invoke('scan-security'),
  getConfig: () => ipcRenderer.invoke('get-config'),
  setAutoGuardian: (enabled) => ipcRenderer.invoke('set-auto-guardian', enabled),
  onStatusUpdate: (cb) => ipcRenderer.on('status-update', (_e, data) => cb(data)),
  onAutoClean: (cb) => ipcRenderer.on('auto-clean', (_e, data) => cb(data)),
  onHotkeyClean: (cb) => ipcRenderer.on('hotkey-clean', (_e, data) => cb(data)),
  onBackendError: (cb) => ipcRenderer.on('backend-error', (_e, msg) => cb(msg)),
});
