const { app, BrowserWindow, ipcMain, globalShortcut } = require('electron');
const { execFile } = require('child_process');
const path = require('path');
const fs = require('fs');

let mainWindow;

// In a packaged build, files listed in "files" get bundled into app.asar, which is
// a virtual archive Node can read but external processes (like powershell.exe) cannot.
// "scripts/**/*" is unpacked alongside app.asar (see package.json "asarUnpack"), so in
// production we must point at app.asar.unpacked instead of the in-archive path.
const scriptsDir = app.isPackaged
  ? path.join(process.resourcesPath, 'app.asar.unpacked', 'scripts')
  : path.join(__dirname, 'scripts');
const scriptPath = path.join(scriptsDir, 'actions.ps1');

const CONFIG = {
  pollMs: 4000,
  vramThreshold: 85,
  autoGuardian: true,
  cooldownMs: 15000,
};
let lastAutoCleanAt = 0;

function runAction(action) {
  return new Promise((resolve, reject) => {
    if (!fs.existsSync(scriptPath)) {
      return reject(`actions.ps1 not found at ${scriptPath}`);
    }
    // SecurityScan walks every running process and Authenticode-checks the suspicious
    // ones, which can take longer than the default window under heavy load.
    const timeout = action === 'SecurityScan' ? 45000 : 20000;
    execFile('powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, '-Action', action],
      { timeout, windowsHide: true },
      (err, stdout, stderr) => {
        if (err) return reject(stderr || err.message);
        try { resolve(JSON.parse(stdout.trim())); }
        catch (e) { reject('Bad JSON from ' + action + ': ' + stdout); }
      }
    );
  });
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 460,
    height: 780,
    resizable: false,
    backgroundColor: '#05070a',
    title: 'ComfyRAM Manager',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

function startPolling() {
  setInterval(async () => {
    try {
      const status = await runAction('Status');
      if (mainWindow) mainWindow.webContents.send('status-update', status);

      const now = Date.now();
      if (CONFIG.autoGuardian &&
          status.vram && status.vram.percent >= CONFIG.vramThreshold &&
          now - lastAutoCleanAt > CONFIG.cooldownMs) {
        lastAutoCleanAt = now;
        const result = await runAction('Free');
        if (mainWindow) mainWindow.webContents.send('auto-clean', result);
      }
    } catch (e) {
      if (mainWindow) mainWindow.webContents.send('backend-error', String(e));
    }
  }, CONFIG.pollMs);
}

ipcMain.handle('get-status', () => runAction('Status'));
ipcMain.handle('free-vram', () => runAction('Free'));
ipcMain.handle('clear-ram', () => runAction('ClearRam'));
ipcMain.handle('detect-comfy', () => runAction('Detect'));
ipcMain.handle('kill-all', () => runAction('KillAll'));
ipcMain.handle('scan-security', () => runAction('SecurityScan'));
ipcMain.handle('get-config', () => CONFIG);
ipcMain.handle('set-auto-guardian', (evt, enabled) => { CONFIG.autoGuardian = !!enabled; return CONFIG; });

app.whenReady().then(() => {
  createWindow();
  startPolling();

  globalShortcut.register('Control+Alt+F', async () => {
    try {
      const result = await runAction('Free');
      if (mainWindow) mainWindow.webContents.send('hotkey-clean', result);
    } catch (e) {
      if (mainWindow) mainWindow.webContents.send('backend-error', String(e));
    }
  });

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('will-quit', () => globalShortcut.unregisterAll());
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
