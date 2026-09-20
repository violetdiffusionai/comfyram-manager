const RING_CIRCUMFERENCE = 2 * Math.PI * 52;

function log(msg, cls = '') {
  const body = document.getElementById('consoleBody');
  const line = document.createElement('div');
  line.className = 'line' + (cls ? ' ' + cls : '');
  const t = new Date().toLocaleTimeString();
  line.textContent = `[${t}] ${msg}`;
  body.appendChild(line);
  body.scrollTop = body.scrollHeight;
  while (body.children.length > 200) body.removeChild(body.firstChild);
}

function setRing(el, percent) {
  const offset = RING_CIRCUMFERENCE * (1 - Math.min(percent, 100) / 100);
  el.style.strokeDashoffset = offset;
}

function renderStatus(status) {
  if (status.vram) {
    document.getElementById('vramValue').textContent = status.vram.percent + '%';
    document.getElementById('vramSub').textContent = `${status.vram.used} / ${status.vram.total} MiB`;
    setRing(document.getElementById('vramRing'), status.vram.percent);
  }
  if (status.ram) {
    document.getElementById('ramValue').textContent = status.ram.percent + '%';
    document.getElementById('ramSub').textContent =
      `${(status.ram.usedMB/1024).toFixed(1)} / ${(status.ram.totalMB/1024).toFixed(1)} GB`;
    setRing(document.getElementById('ramRing'), status.ram.percent);
  }
  const pill = document.getElementById('comfyPill');
  const pillText = document.getElementById('comfyPillText');
  if (status.comfy && status.comfy.online) {
    pill.className = 'comfy-pill online';
    pillText.textContent = 'COMFYUI :' + status.comfy.port;
  } else {
    pill.className = 'comfy-pill offline';
    pillText.textContent = 'COMFYUI OFFLINE';
  }
}

document.getElementById('btnFree').addEventListener('click', async () => {
  log('Manual free triggered...');
  try {
    const r = await window.guardian.freeVram();
    log(`VRAM ${r.before.percent}% -> ${r.after.percent}% | trimmed ${r.trimmedProcesses} proc | tab reloaded: ${r.reloadedTab}`, 'ok');
  } catch (e) { log('Free failed: ' + e, 'err'); }
});

document.getElementById('btnClearRam').addEventListener('click', async () => {
  log('Clearing RAM (trimming working sets)...');
  try {
    const r = await window.guardian.clearRam();
    log(`RAM ${r.before.percent}% -> ${r.after.percent}% | trimmed ${r.trimmed} processes`, 'ok');
  } catch (e) { log('Clear RAM failed: ' + e, 'err'); }
});

document.getElementById('btnDetect').addEventListener('click', async () => {
  log('Scanning for ComfyUI...');
  try {
    const r = await window.guardian.detectComfy();
    log(r.online ? `ComfyUI found on port ${r.port}` : 'ComfyUI not detected on any known port', r.online ? 'ok' : 'err');
  } catch (e) { log('Detect failed: ' + e, 'err'); }
});

document.getElementById('btnSecurity').addEventListener('click', async () => {
  log('Running security scan (checking for fraudulent/spoofed processes)...');
  try {
    const r = await window.guardian.scanSecurity();
    renderSecurity(r);
    if (r.flagged === 0) {
      log(`Security scan clean — ${r.scanned} processes checked, 0 flagged.`, 'ok');
    } else {
      log(`Security scan flagged ${r.flagged} of ${r.scanned} process(es). See panel above log.`, 'warn');
    }
  } catch (e) { log('Security scan failed: ' + e, 'err'); }
});

function renderSecurity(result) {
  const header = document.getElementById('secHeader');
  const list = document.getElementById('secList');
  list.innerHTML = '';

  if (!result.flagged) {
    header.textContent = `SECURITY: CLEAR (${result.scanned} scanned)`;
    header.className = 'sec-header sec-clear';
    return;
  }

  const worst = result.findings[0].level;
  header.textContent = `SECURITY: ${result.flagged} FLAGGED (${result.scanned} scanned)`;
  header.className = 'sec-header sec-' + worst.toLowerCase();

  result.findings.forEach((f) => {
    const item = document.createElement('div');
    item.className = 'sec-item sec-item-' + f.level.toLowerCase();
    item.innerHTML =
      `<div class="sec-item-top"><span class="sec-badge sec-badge-${f.level.toLowerCase()}">${f.level}</span>` +
      `<span class="sec-name">${f.name}</span><span class="sec-pid">PID ${f.pid}</span></div>` +
      `<div class="sec-path">${f.path}</div>` +
      `<div class="sec-reasons">${f.reasons.join(' • ')}</div>`;
    list.appendChild(item);
  });
}

const modal = document.getElementById('confirmModal');
document.getElementById('btnKillAll').addEventListener('click', () => {
  document.getElementById('modalTitle').innerHTML = '&#9888; TERMINATE ALL PYTHON + NVIDIA CONTAINERS?';
  modal.classList.add('show');
});
document.getElementById('modalCancel').addEventListener('click', () => modal.classList.remove('show'));
document.getElementById('modalConfirm').addEventListener('click', async () => {
  modal.classList.remove('show');
  log('Killing all python + NVIDIA container processes...');
  try {
    const r = await window.guardian.killAll();
    log(`Terminated ${r.count} process(es).`, 'ok');
  } catch (e) { log('Kill-all failed: ' + e, 'err'); }
});

document.getElementById('autoGuardianToggle').addEventListener('change', async (e) => {
  await window.guardian.setAutoGuardian(e.target.checked);
  log('Auto-Guardian ' + (e.target.checked ? 'ENABLED' : 'DISABLED'));
});

window.guardian.onStatusUpdate(renderStatus);
window.guardian.onAutoClean((r) => {
  log(`AUTO-GUARDIAN triggered clean: ${r.before.percent}% -> ${r.after.percent}%`, 'ok');
});
window.guardian.onHotkeyClean((r) => {
  log(`HOTKEY clean: ${r.before.percent}% -> ${r.after.percent}%`, 'ok');
});
window.guardian.onBackendError((msg) => {
  log('Backend error: ' + msg, 'err');
});

function tickClock() {
  document.getElementById('clock').textContent = new Date().toLocaleTimeString();
}
setInterval(tickClock, 1000);
tickClock();

(async () => {
  log('ComfyRAM Manager online. Watching VRAM...');
  try {
    const status = await window.guardian.getStatus();
    renderStatus(status);
  } catch (e) { log('Initial status fetch failed: ' + e, 'err'); }
})();
