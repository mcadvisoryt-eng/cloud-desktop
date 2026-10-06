# MOBILE — a real Android OS, free, on GitHub Actions

`android-desktop.yml` runs **full Android** on a free `ubuntu-latest` runner and
lets you use it from your phone's browser. No emulator, no KVM, no paid larger
runner, no ISO.

## Why this works (and why the emulator route doesn't)

An Android *emulator* needs hardware virtualisation (KVM), which GitHub only
enables on **larger runners** — always billed, and only on Team/Enterprise
plans. So the emulator route is closed.

**redroid** ("remote android") takes a different path: it runs Android's
userspace **directly as a Docker container against the host kernel** — no CPU
emulation, no VM layer [cite:dac8554d]. The one thing it needs is the `binder`
kernel driver, and the **x86_64 `ubuntu-latest` runner image ships
`binder_linux`** with passwordless sudo [cite:7a8bba09],[cite:44111ce7]. That's
the whole trick — and it's why this is free.

## Connect from your phone

1. Make sure Tailscale is on (same tailnet as your other desktops).
2. Open your phone's browser at:

   ```
   http://cloudpc-android.<your-tailnet>.ts.net:8000
   ```

   That's **ws-scrcpy**, a browser client for scrcpy that works with redroid
   [cite:cb205d00] — tap to touch, multi-touch, keyboard, clipboard and
   rotation all work, so it behaves like a phone.

You can also reach it over ADB (`cloudpc-android:5555`) if you'd rather use a
native scrcpy client from a computer.

The default screen is phone-shaped (720×1280). Change it with
`androidboot.redroid_width/height/dpi` in the workflow [cite:fe21eb5b].

## Pick your Android version

Set `ANDROID_IMAGE` in the workflow env, e.g.:

```
redroid/redroid:13.0.0-latest      (default)
redroid/redroid:12.0.0_64only-latest
redroid/redroid:16.0.0_64only-latest
```

## What to expect, honestly

- **This is real Android** — you can install and run Android apps, browse, etc.
- **No Google Play services** by default (these are AOSP images). Sideload APKs
  via `adb install`, or use an image/target that includes them if you need Play.
- **ARM-only apps** run through a translation layer on an x86_64 host, so they
  may be slower or not work. Pure-Java/native-x86 apps are fine.
- **No persistence yet.** `/var/redroid-data` is kept for the life of the run,
  but isn't backed up to rclone in this version — every session starts fresh.
  (Same pattern as the other variants is easy to add later.)
- **6-hour cap and the same off-label-use status** as the Linux and Windows
  variants.

## Troubleshooting

The workflow prints a diagnostics block after loading the kernel modules. If it
says `binder NOT in /proc/filesystems`, the runner image has changed and the
container won't boot — that's the one thing to check first.

- **Container exits immediately:** run `sudo docker logs android` — it will say
  if binder is missing.
- **`http://…:8000` doesn't load:** check the ws-scrcpy log line in the
  "Serve Android + run session" step; ws-scrcpy is a small, older Node project
  and is the most likely thing to need a tweak.
- **Black screen in the browser:** reload; try a different decoder in the
  ws-scrcpy UI (WebCodecs/MSE).
- **Can't reach it at all:** confirm `cloudpc-android` shows up in Tailscale.

## Honest status

The Android-boots-and-is-reachable part is solid (redroid on a runner with
binder is a documented, working pattern). The **browser viewer** (ws-scrcpy) is
the experimental piece — it's a small older project, so expect to iterate there
first. Tell me what the logs say and I'll fix it, the same way we did the dbus
and shutdown-signal issues.
