# MOBILE — a real Android phone in the cloud, free

`android-desktop.yml` runs **full Android with Google Play** on a free
`ubuntu-latest` runner, backed up to your encrypted remote, and lets you use it
from your phone's browser. No emulator, no KVM, no paid larger runner, no ISO.

---

## Why this works (and why the emulator route doesn't)

An Android *emulator* needs hardware virtualisation (KVM), which GitHub only
enables on **larger runners** — always billed, Team/Enterprise plans only. So
the emulator route is closed.

**redroid** takes a different path: it runs Android's userspace **directly as a
Docker container against the host kernel** — no CPU emulation, no VM layer. The
one requirement is the `binder` kernel driver, and the **x86_64 `ubuntu-latest`
runner ships `binder_linux`** with passwordless sudo. That's the whole trick —
and why it's free. (Source: redroid-doc, github.com/remote-android/redroid-doc.)

**Google Play** is added by baking GApps into the redroid image with
`ayasa520/redroid-script`, which patches the image without recompiling it. It
uses **LiteGapps**, which ships real x86_64 builds — MindTheGapps is built for
arm64, and its Google apps crash on this x86_64 host. The same script adds
**houdini** (so ARM apps run on the x86_64 host) and can add **Widevine**
(DRM playback).

---

## Setup, step by step

### 1. Secrets
Nothing new. It reuses `TS_AUTHKEY` and `DESKTOP_PASSWORD` (plus optional
`RESTART_PAT`, and `RCLONE_CONFIG` for backup). See `SECRETS.md`.

### 2. Start it
```
gh workflow run android-desktop.yml --repo <owner>/<repo>
gh run list --repo <owner>/<repo>
```
The first run is the slowest: it loads the binder module, restores your data,
**builds the Google-Play-enabled image**, boots Android, and **certifies the
device**. Budget ~10–20 min the first time; later runs are faster.

### 3. Tailscale on
On the phone, Tailscale connected to the same tailnet — a `cloudpc-android`
device appears.

### 4. Open it in your phone's browser

Three viewers run at once, so if one fails the next may not:
```
http://cloudpc-android.<your-tailnet>.ts.net:3200/          serve-avd  (try first)
http://cloudpc-android.<your-tailnet>.ts.net:6080/vnc.html  noVNC
cloudpc-android.<your-tailnet>.ts.net:5900                  raw VNC (native app)
```
- **`:3200` — serve-avd**: the simplest chain (`adb screenrecord` → WebCodecs in
the browser). No Xvfb/scrcpy/x11vnc/websockify to go wrong, so start here.
- **`:6080` — noVNC**: VNC in the browser, backed by scrcpy → Xvfb → x11vnc.
- **`:5900` — raw VNC**: for a native VNC app (RealVNC Viewer, bVNC) — the
  closest thing to the Windows App for RDP.

### 5. Sign in to Google
Open the Play Store and sign in with your Google account.

### 6. Device certification — automatic
The workflow reads the device's Android ID at startup and registers it on
Google's official uncertified-device page for you, so Play stops saying "device
not certified". If Google's form rejects the automatic request, the run log
prints the ID — paste it at <https://www.google.com/android/uncertified/> once
and you're done. Because your data dir is backed up and restored, the ID is
stable across sessions, so this is effectively one-time.

### 7. Install apps
Play Store in the browser UI, or sideload over adb:
```
adb connect cloudpc-android:5555
adb install yourapp.apk
```

---

## Integrity — what's automatic, and what isn't

Worth being precise here, because "integrity" means two different things:

**Automatic (done for you at startup):**
- **Play Protect certification** — the device ID is read and registered with
  Google automatically (step 6), so the "device not certified" warning clears
  and the Play Store behaves normally.
- **Widevine L3** is baked into the image, so DRM playback works at L3 (SD
  quality) — the software tier.
- **Root is ON by default (Magisk, systemless).** That's the *opposite* of the
  integrity story: apps that check for root — many banking, payment and some
  streaming apps — will refuse to run. If you'd rather maximise compatibility,
  remove `-m` from the redroid-script line.

**Not possible — and I won't fake it:**
- **Play Integrity API / SafetyNet hardware attestation.** These check for a
  *verified boot chain and a hardware-backed keystore*. A container Android has
  neither, so it cannot pass them, and there is no configuration that fixes
  that. Apps that *require* hardware attestation — many banking apps, some
  games, and DRM L1 (HD/4K streaming) — will not work here.
- I'm not going to add root-hiding, keybox spoofing or attestation-bypass
  modules to defeat those checks. That's circumventing a security control, and
  it's a bad idea to trust a box holding your Google account with it anyway.

If an app you need insists on hardware attestation, a real phone or a cloud
Android service built on certified hardware is the only honest answer.

---

## Backup and persistence

Android data lives at `/var/redroid-data` and is backed up to `crypt1:android`
on your encrypted remote:

- **Restored** at the start of every session (before Android boots).
- **Backed up** every 30 minutes, and once more when the session ends.

Set the `RCLONE_CONFIG` secret and it just works (see `RCLONE.md`).

**A backup never takes the session down.** If a backup or a restore does not
complete, the workflow:

1. **retries once**, then
2. writes the rclone output to a log and **uploads it to `crypt1:logs/`**
   (`android-backup-<stamp>.log`, or `android-restore-<stamp>.log`), and
3. **carries on** — the session keeps running (or starts) *without* the backup
   rather than dying.

So a flaky transfer costs you one snapshot, not the desktop. You can read those
failure logs from your Drive any time, under `cloud-desktop/logs/`.

Caveat: the backup is taken from a *running* Android, so it's crash-consistent
at best — treat the last few minutes as unreliable. The 30-minute cadence is
your safety net.

**Caches are excluded.** `scripts/android-excludes.txt` keeps caches, dalvik
and oat out of both the backup *and* the restore. Without it a restore pulled
the caches back too and took an **hour**; with it the handoff is back to a
couple of minutes. Apps, accounts and app data are all still included.

**The Android screen is kept awake** at boot (`svc power stayon true`, screen
timeout disabled, and a wake keyevent). A sleeping Android screen shows as a
plain black viewer.

---

## Keeping the name stable (important)

Every run joins your tailnet as `cloudpc-android`. If dead nodes from finished
runs aren't removed, Tailscale renames the live one to `cloudpc-android-1`
(`-2`, …) and the plain name resolves to a corpse — which looks exactly like
"the URL won't load".

**Fix: make `TS_AUTHKEY` Ephemeral.** Regenerate it in the Tailscale admin
console with *Ephemeral: yes*, then:
```
gh secret set TS_AUTHKEY --repo <owner>/<repo>
```
Dead runners then remove themselves and the name always belongs to the live
one. The run log's `--- tailscale status ---` line shows the name actually
assigned, so you can confirm.

---

## Tuning

### Making it less laggy (do this first)

ws-scrcpy streams through your browser, and **the decoder you pick matters more
than anything else**. In the device row:

1. **Pick `H264 Converter`** (Media Source Extensions). It uses your phone's
   hardware H.264 decoder. `Broadway.js` and `Tiny H264` are *software* WASM
   decoders — they are the single biggest cause of lag. Switching to MSE is the
   one change that matters most.
2. Keep the dropdown on **`proxy over adb`** (correct for redroid).
3. Use **`Configure stream`** to lower `max size` (e.g. 540) and set a modest
   bitrate — less to encode, less to send, less lag.

### Honest floor

Even fully tuned, this is not as snappy as the Windows/RDP desktop: RDP is a
mature, heavily optimised protocol, while ws-scrcpy is a device → scrcpy-server
→ adb → Node proxy → WebSocket → browser pipeline. And the runner is in a US
Azure region, so ~180–250 ms of network round-trip is unavoidable here. For
real low latency, run redroid on the Indian-region VM (`CLOUD-VM.md`).

### Other knobs

| What | Where |
|---|---|
| Screen size | `androidboot.redroid_width/height/dpi` in the "Start Android" step (default 540×960 @ 240, lowered for latency) |
| Frame rate | `androidboot.redroid_fps` (default 30) |
| Android version | `ANDROID_VERSION` (default `13.0.0`) |
| Google Play package | `-lg` (LiteGapps, x86_64). `-mtg` MindTheGapps is arm64 and crashes here; `-g` OpenGApps is Android 11 only |
| ARM app translation | `-i` (houdini) — remove if it causes trouble |
| Widevine DRM | `-w` |
| Root (Magisk) | on by default (`-m`); remove it for better app compatibility |
| Session length | `SESSION_MINUTES` (default 330) |

---

## What to expect, honestly

- **Real Android with the Play Store**, certified automatically.
- **ARM apps** run through houdini translation — most work, some are slow or
  refuse to install.
- **First boot is slow** (image build). Later boots faster.
- **6-hour cap** and the same off-label-use status as the other variants.
- **The viewer is the experimental part.** Booting Android via redroid with
  binder is a documented pattern; ws-scrcpy is a small older Node project and is
  most likely to need a tweak.

## Troubleshooting

The workflow prints a binder diagnostics block right after loading the modules.
If it says `binder NOT in /proc/filesystems`, the runner image changed and
Android won't boot — check that first.

- **Container exits immediately** → `sudo docker logs android`.
- **GApps build failed** → the workflow falls back to plain AOSP redroid (no
  Play Store) and warns; check the redroid-script output.
- **`…:6080/vnc.html` doesn't load** → check the `--- xvfb ---`, `--- scrcpy ---`,
  `--- x11vnc ---` and `--- websockify ---` tails printed by the
  "Serve Android + run session" step; they name whichever piece failed.
- **A tool says `MISSING:`** in the "Install packages" step → that package
  didn't install; that's why its viewer is dead.
- **Play Store says "device not certified"** → the run log prints the Android
  ID; submit it at <https://www.google.com/android/uncertified/>.
- **Play Store crashes / bounces you to the home screen** → almost always an
  architecture mismatch: arm64 Google apps on an x86_64 host. The workflow now
  uses LiteGapps (x86_64). If it still crashes, check the
  "Diagnostics — GApps state" step: `ro.product.cpu.abilist` should start with
  `x86_64`, and the crash log will name the failing package.
- **An app says "your device isn't compatible"** → it needs hardware
  attestation, which can't be provided (see Integrity above).
