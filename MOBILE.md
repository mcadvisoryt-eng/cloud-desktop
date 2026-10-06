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
Docker container against the host kernel** — no CPU emulation, no VM layer
[cite:dac8554d]. The one requirement is the `binder` kernel driver, and the
**x86_64 `ubuntu-latest` runner ships `binder_linux`** with passwordless sudo
[cite:7a8bba09],[cite:44111ce7]. That's the whole trick — and why it's free.

**Google Play** is added by baking GApps into the redroid image with
`ayasa520/redroid-script`, which patches the image without recompiling it
[cite:e28c4db6]. It uses **MindTheGapps**, because OpenGApps only supports
Android 11 [cite:32a8a509]. The same script adds **houdini** (so ARM apps run
on the x86_64 host) and **Magisk** (root).

---

## Setup, step by step

### 1. Secrets
Nothing new to add. It reuses the same two required secrets:
`TS_AUTHKEY` and `DESKTOP_PASSWORD` (plus optional `RESTART_PAT`,
`RCLONE_CONFIG` for backup). See `SECRETS.md`.

### 2. Start it
```
gh workflow run android-desktop.yml --repo <owner>/<repo>
gh run list --repo <owner>/<repo>
```
The first run is the slowest: it loads the binder module, restores your data,
**builds the Google-Play-enabled image**, then boots Android. Budget ~10–20 min
for the first boot; later runs are faster once the image layer is cached.

### 3. Make sure Tailscale is on
On the phone, Tailscale connected to the same tailnet. You'll see a
`cloudpc-android` device appear.

### 4. Open it in your phone's browser
```
http://cloudpc-android.<your-tailnet>.ts.net:8000
```
That's **ws-scrcpy**, a browser client for scrcpy that works with redroid
[cite:cb205d00] — tap to touch, multi-touch, keyboard, clipboard, rotation.
(The run log also prints the tailnet IP if you prefer that.)

### 5. Sign in to Google (first time only)
Open the Play Store and sign in with your Google account. It works, but the
device will be flagged **"not Play Protect certified"** — see the next step.

### 6. Certify the device (so Play works properly)
Google checks the device ID. Get it and register it once:

```bash
# on any machine on your tailnet with adb installed
adb connect cloudpc-android:5555
adb root
adb shell 'sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \
  "select * from main where name = \"android_id\";"'
```
Copy the number it prints and register it at
<https://www.google.com/android/uncertified/> [cite:e28c4db6],[cite:e9ae50c8].
Give it a few minutes, then the Play Store behaves normally.

### 7. Install apps
Use the Play Store in the browser UI, or sideload over adb:
```bash
adb connect cloudpc-android:5555
adb install yourapp.apk
```

---

## Backup and persistence

Your Android data lives at `/var/redroid-data` on the runner and is backed up to
`crypt1:android` on your encrypted remote:

- **Restored** at the start of every session (before Android boots).
- **Backed up** every 30 minutes, and once more when the session ends.

So apps you install and data you create survive across sessions — set up the
`RCLONE_CONFIG` secret and it just works (`RCLONE.md`).

Caveat: the backup is taken from a *running* Android, so it's crash-consistent
at best — treat the last few minutes as unreliable. For anything critical, the
periodic 30-minute cadence is your safety net.

---

## Tuning

| What | Where |
|---|---|
| Android version | `ANDROID_VERSION` (default `13.0.0`) |
| Screen | `androidboot.redroid_width/height/dpi` in the "Start Android" step |
| Google Play package | `-mtg` in the redroid-script line (`-lg` for LiteGapps, `-g` OpenGApps = 11 only) |
| ARM app translation | `-i` (houdini) — remove it if it causes trouble |
| Session length | `SESSION_MINUTES` (default 330) |

---

## What to expect, honestly

- **Real Android with the Play Store.** AOSP + MindTheGapps, so Play Services
  work after you certify the device (step 6).
- **ARM apps** run through houdini translation — most work, some are slow or
  refuse to install. Pure x86/Java apps are native.
- **First boot is slow** (image build). Subsequent boots faster.
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
- **Play Store says "device not certified"** → do step 6.
