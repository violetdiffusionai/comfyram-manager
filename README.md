# ComfyRAM Manager

A small cybernoir control panel for the memory ComfyUI is holding. It watches
VRAM and system RAM, frees them on demand or on its own, and finds your running
ComfyUI without being told where it is.

Windows only. Electron front end, PowerShell underneath.

## Quick guide

**Install** — grab the latest `ComfyRAM Manager Setup <version>.exe` from
[Releases](https://github.com/violetdiffusionai/comfyram-manager/releases) and
run it. Nothing to configure; it finds ComfyUI by scanning for its port.

**The window** is 460×780 and does not resize. It polls every 4 seconds and
shows VRAM used/total, system RAM, and whether ComfyUI is online and on which
port.

**Ctrl+Alt+F** frees VRAM from anywhere, without focusing the window. This is
the feature worth remembering — it works mid-generation, from inside ComfyUI,
from a game, from anywhere.

### The buttons

| Action | What it does |
|---|---|
| **Free** | Calls ComfyUI's own `/free` on the detected port, trims process working sets, and reloads the ComfyUI browser tab. Reports VRAM before and after. |
| **Clear RAM** | System memory only — file cache and working sets. Leaves the GPU alone. |
| **Detect** | Re-scans for ComfyUI's port. Use after starting or restarting it. |
| **Security Scan** | Walks running processes and Authenticode-checks the suspicious ones. Slower than the rest — it gets 45 seconds rather than 20. |
| **Kill All** | **Destructive.** Terminates every Python process and container it finds. That includes ComfyUI itself and any unsaved work in it. It is the last resort, not a cleanup. |

### Auto Guardian

On by default. When VRAM crosses **85%**, it runs Free automatically, then
waits 15 seconds before it will fire again. Toggle it from the panel.

The thresholds live in the `CONFIG` object at the top of
[`main.js`](main.js) — `pollMs`, `vramThreshold`, `autoGuardian`, `cooldownMs`.
There is no settings file yet; change them there and rebuild.

## Why it exists

ComfyUI holds model weights across runs on purpose — reloading 10 GB per image
would be absurd. The cost is that on a 12 GB card, what decides whether the
next generation fits is usually what is still resident from the last one, and
nothing surfaces that. It arrives as a failed run rather than as a number
anyone could have looked at first.

`/free` alone is also not the whole job. It only touches what ComfyUI itself
allocated, and it sets a flag on the prompt queue rather than acting
immediately. Working sets, file cache and a browser tab pinning GPU memory are
all outside its reach, which is why Free here does four things rather than one.

## Build from source

```bash
npm install
npm start        # run it
npm run dist     # build the Windows installer
```

`scripts/**/*` must stay unpacked from the asar. PowerShell cannot read inside
a virtual archive, so a packed `actions.ps1` is a script that does not exist as
far as `powershell.exe` is concerned. `asarUnpack` in `package.json` handles
this, and `main.js` resolves `app.asar.unpacked` in packaged builds.

## Layout

```
main.js                  window, polling loop, Auto Guardian, global hotkey, IPC
preload.js               contextBridge surface
renderer/                the panel — index.html, renderer.js, style.css
scripts/actions.ps1      dispatches one of six actions, answers in JSON
scripts/GuardianCore.ps1 the actual work: VRAM/RAM reads, port discovery, frees
```

`contextIsolation` is on and `nodeIntegration` is off. The renderer reaches the
system only through the handful of IPC channels in `preload.js`.

## A note on this repository

The published history starts from the source shipped inside the 1.1.0 build.
Every runtime file — `main.js`, `preload.js`, the renderer and both PowerShell
scripts — is verbatim from that build. The build scaffolding around it
(`devDependencies`, the `build` block, `.gitignore`, this README) was
reconstructed, because electron-builder strips it from a packaged app. The
`build` block restates what the shipped `main.js` already assumes — that
`scripts/**/*` is unpacked — and both pinned versions resolve, but the
reconstruction has not been through a full clean-clone build yet. It is also
not the original commit history.

## License

MIT — see [LICENSE](LICENSE).
