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
uses **MindTheGapps**, because OpenGApps only supports Android 11. The same
script adds **houdini** (so ARM apps run on the x86_64 host) and can add
**Widevine** (DRM playback).

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
```
http://cloudpc-android.<your-tailnet>.ts.net:8000
```
That's **ws-scrcpy**, a browser client for scrcpy that works with redroid — tap
to touch, multi-touch, keyboard, clipboard, rotation.

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
- **No root by default.** redroid is already rootable with `adb root`, so we
  deliberately do **not** install Magisk: root is what makes integrity checks
  complain. If you specifically want Magisk, add `-m` to the redroid-script
  line — but accept that some apps will then refuse to run.

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

Caveat: the backup is taken from a *running* Android, so it's crash-consistent
at best — treat the last few minutes as unreliable. The 30-minute cadence is
your safety net.

---

## Tuning

| What | Where |
|---|---|
| Android version | `ANDROID_VERSION` (default `13.0.0`) |
| Screen | `androidboot.redroid_width/height/dpi` in the "Start Android" step |
| Google Play package | `-mtg` in the redroid-script line (`-lg` LiteGapps, `-g` OpenGApps = 11 only) |
| ARM app translation | `-i` (houdini) — remove if it causes trouble |
| Widevine DRM | `-w` |
| Root (Magisk) | add `-m` — but see the Integrity section first |
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
- **`http://…:8000` doesn't load** → check the ws-scrcpy log in the
  "Serve Android + run session" step.
- **Play Store says "device not certified"** → the run log prints the Android
  ID; submit it at <https://www.google.com/android/uncertified/>.
- **An app says "your device isn't compatible"** → it needs hardware
  attestation, which can't be provided (see Integrity above).
