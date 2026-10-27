# Landscape: who else is doing this, and what to borrow

A survey of the open-source projects that overlap with this repo, so the
"build it ourselves vs modify theirs" decision is made on facts.

Repo links are plain URLs; star counts are approximate as of this survey.

---

## 1. Direct overlap: cloud desktops on GitHub Actions

These are the projects doing the same trick — a GUI desktop on a hosted runner,
tunnelled out.

### `pdev-labs/Free-Github-Actions-RDP-for-App-Testing` — the closest match
https://github.com/pdev-labs/Free-Github-Actions-RDP-for-App-Testing

A Python TUI that provisions desktops on runners. GPLv3.

**What it has that we don't:**
- **Custom ISO booting** via QEMU nested virtualisation — boots *any* `.iso`
  (their examples: custom Linux spins, Windows PE, BSD), with **automatic
  splitting for ISOs over GitHub's 2 GB limit** and a **P2P mode** that streams
  an ISO from your local disk into the runner instead of uploading it.
- **Multi-OS**: Linux, Windows, macOS, plus the custom-ISO path.
- **Desktop choice**: XFCE, GNOME, KDE Plasma, i3wm, or headless.
- **Four tunnel engines**: Pinggy (free, anonymous, 60-minute limit with an
  automatic tunnel-restart trick), ngrok, Cloudflare Tunnel, Tailscale.
- **Audio redirection** (Windows `Audiosrv`, Linux `pulseaudio-module-xrdp`).
- **PAM patching** so `xrdp` authentication works inside the runner container.
- ARM emulation via QEMU.

**What it does not have:** any persistence. No backups, no profile restore, no
auto-restart. Each session is a blank machine, and when the run ends everything
is gone.

### Others, roughly by how much is worth reading

| Repo | Transport | Worth looking at for |
|---|---|---|
| https://github.com/ammar0xff/GitHub_Machines | Cloudflare + bore | **Best UX**: a PWA launcher that starts/stops machines and shows live links; browser terminals |
| https://github.com/HARAJIT05/rdp | Tailscale | Same transport as ours; clean minimal Windows RDP |
| https://github.com/lingyicute/Action-ssh | Cloudflare Tunnel | KDE desktop, ARM variants |
| https://github.com/agusibrahim/freedesktop | ngrok | Simplest possible template |
| https://github.com/PRO-E5/RDP-E5 | ngrok | Windows + macOS VNC |
| https://github.com/airsquared/reverse-linux-vnc-github-actions | ngrok | Linux VNC instead of RDP |
| https://github.com/milqaj/windows-github-rdp | ngrok | Minimal Windows RDP |

**Where this repo is genuinely stronger than all of them:** encrypted profile
persistence across sessions (`crypt1:home`, `crypt1:winhome`, `crypt1:chrome`),
automatic restart (pre-queue + watchdog + daily cron), Tailscale-only access
(no public tunnel URL that anyone could hit), the lock-safe Chrome profile
capture, and locale/apps done for IST.

**Where they are stronger:** custom ISO support, audio, desktop-environment
choice, and a much friendlier first-run experience.

---

## 2. Streaming stacks — the alternative to xrdp

xrdp is fine but it is 2000s technology. These replace the whole transport.

| Project | What it is | Licence |
|---|---|---|
| https://github.com/m1k1o/neko | WebRTC virtual desktop/browser in Docker, multi-user | Apache-2.0 (~22k stars) |
| https://github.com/selkies-project/selkies | Low-latency HTML5 remote desktop, GPU-accelerated, WebSockets with opt-in WebRTC | MPL-2.0 (~2.4k) |
| https://github.com/KasmTech/KasmVNC | Modern web VNC server (breaks from RFB on purpose) | GPL-3.0 (~5.3k) |
| https://github.com/linuxserver/docker-baseimage-selkies | Selkies base images: XFCE/KDE/etc. on many distros | GPL-3.0 |
| https://github.com/muddyland/cove | Kasm-style VDI built on Selkies + Tailscale + Gluetun | GPL-3.0 |

**Selkies is the interesting one.** LinuxServer.io replaced KasmVNC with Selkies
in their `webtop` images, citing "greatly increased performance, fidelity, and
feature set". It streams to any modern browser with clipboard, audio and
gamepad support.

**The trade-off for us:** the browser-streamed stacks are all *browser* clients.
RDP via the Windows App is what has felt smoothest to this user, and Selkies
would mean switching to a browser tab. Worth prototyping only if xrdp latency
keeps disappointing.

---

## 3. Making Windows itself better (the legitimate route)

None of these redistribute a modified ISO; they apply changes to a licensed
install. One curated list says it plainly: *"Do not download unofficial
pre-modified Windows ISOs. Use a legitimate Microsoft image and the project's
published playbook or builder."*

| Project | What it is | Licence |
|---|---|---|
| https://github.com/ChrisTitusTech/winutil | Install/debloat/tweaks/updates, with `Standard`/`Minimal`/`Advanced` **presets** for unattended use | MIT (~65k) |
| https://github.com/Raphire/Win11Debloat | PowerShell debloat, CLI + audit mode, exportable settings | MIT (~61k) |
| https://github.com/Atlas-OS/Atlas | AME Wizard **playbook** — explicitly does not redistribute an ISO and does not touch activation | GPL-3.0 (~22k) |
| https://github.com/meetrevision/playbook | ReviOS playbook (AME Wizard) | CC-BY-SA-4.0 |
| https://github.com/flick9000/winscript | Web UI that composes a debloat script + `autounattend.xml` | GPL-3.0 |
| https://github.com/just-maik/win-opti-resources | Curated comparison list with risk ratings | CC0 |

**`winutil` is the one to adopt first** — it has presets, so a workflow can run
it unattended: `& ([ScriptBlock]::Create((irm https://christitus.com/win))) -Preset Standard`.

**Important caveat for this repo:** Atlas, ReviOS, Win11Debloat and winutil
target **Windows 10/11 consumer builds**. Our runner is **Windows Server 2025**,
so some tweaks will no-op or apply differently. This is exactly why the
`Customise the desktop` step in `windows-desktop.yml` does its own targeted
changes rather than shelling out to a consumer debloater.

---

## 4. The decision this supports

**On custom ISOs:** don't build it. `pdev-labs/...` already implements QEMU
nested-virt ISO boot, including the >2 GB splitting and P2P streaming that are
the annoying parts. Fork it, or lift its approach, rather than re-deriving it.
See `CUSTOM-ISO.md` for the licensing line and why it is a poor trade.

**On the Windows experience:** adopt `winutil`'s preset mechanism where it
applies, and keep our own targeted step for the Server-specific bits. Do not
switch to a fan-made ISO.

**On streaming:** stay on RDP for now. Prototype Selkies only if latency is the
blocking complaint.

**On what we already do better:** persistence, restart reliability, and
Tailscale-only access. Those are the parts worth keeping and hardening — they
are the difference between a demo and something you can actually use.

---

## Worth stealing outright

1. **The PWA launcher** from `GitHub_Machines` — one tap to start/stop and copy
   the connection string beats reading Actions logs.
2. **`winutil -Preset Standard`** as a single unattended debloat call.
3. **Audio redirection** (`pulseaudio-module-xrdp` on Linux) — a desktop without
   sound is half a desktop.
4. **Desktop-environment choice** — letting the user pick XFCE/GNOME/KDE would
   have saved this repo a long XFCE debugging detour.
