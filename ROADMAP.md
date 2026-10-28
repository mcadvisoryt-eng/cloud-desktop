# Roadmap — what's left to make this the best it can be

State as of the last API check: latest commit `f4b9a19` (desktop-environment
choice). Everything below is ordered by what actually blocks you.

---

## 1. Blocked on you (nothing I can do from here)

| # | Item | Why it's blocked |
|---|---|---|
| 1 | **Paste `windows-desktop.yml`** — swaps delisted uBlock Origin (MV2) for uBlock Origin Lite (MV3) and pins the icons | I cannot push: the commit API returns a Cloudflare block, and `GH_TOKEN` in the agent environment is invalid so `git push` cannot authenticate |
| 2 | **Paste `maintenance.yml`** — adds `crypt1:chrome` / `crypt1:winhive` reporting | same |
| 3 | **Enable Pages** — Settings → Pages → Source: *GitHub Actions* | `enablement: true` needs admin rights the token lacks; both launcher runs failed with "Pages site not found" |
| 4 | **Fix the agent's push access** — a valid token with `contents: write`, or a working GitHub App connection | without it, every change needs a manual paste |

---

## 2. Built but never proven — verify before trusting

These exist in code but no run has demonstrated them end to end. This is the
most valuable next work, because everything else is speculation until they hold.

| # | Item | How to prove it |
|---|---|---|
| 5 | `crypt1:chrome` actually receives the Chrome profile | run `maintenance` with `action=backup` and read the new reporting section |
| 6 | `crypt1:winhive` actually receives `NTUSER.DAT` | same run — this is the one that decides whether your logins survive a handover |
| 7 | **Linux audio** (`pulseaudio-module-xrdp`) built successfully | the desktop step logs it; also audible sound over RDP |
| 8 | Windows desktop renders over RDP (not just "port open") | `verify` currently screenshots only the Linux desktop — it should screenshot Windows too |

---

## 3. Worth building next, in order

| # | Item | Why it matters |
|---|---|---|
| 9 | **A shared folder in the encrypted Drive** (`crypt1:share`, synced both ways on both desktops) | the biggest real gap. Getting a file from your phone into the desktop, or out again, is painful today. A Drive folder solves it with zero new infrastructure — you drop a file in the Drive app, it appears on the desktop |
| 10 | **`verify` tests both desktops** and writes the result to `crypt1:logs/verify-latest.log` | today a Windows breakage is invisible until you try to connect |
| 11 | **Launcher: desktop choice + session length** | the workflow already accepts `desktop` and `session_minutes`; the launcher should pass them |
| 12 | **A "reset my profile" escape hatch** | when a profile goes bad, the current recovery is editing a workflow. A one-shot dispatch input that clears `crypt1:winhome`/`crypt1:winhive` would be much safer than a stuck logon |
| 13 | **Tailscale ACLs** limiting which devices may reach `cloudpc:3389` | today any device on your tailnet can. Cheap hardening |
| 14 | **`STATUS.md` refresh** | it is the running log and has drifted well behind reality |

---

## 4. Known limits — not fixable on free hosted runners

Worth stating plainly so nobody keeps trying:

- **Restart latency after an early death.** A dead runner cannot restart itself,
  so recovery depends on GitHub's scheduler — which in practice fires every few
  hours, not every 10 minutes. The pre-queue hand-off is the reliable layer.
- **RDP latency.** The runner's region is not selectable, so latency is whatever
  the distance gives you. The only real fix is an India-region host, which means
  a card — `CLOUD-VM.md` covers it.
- **6-hour cap.** Sessions are 345 minutes, comfortably inside it.
- **Custom ISO** means a nested VM inside a nested VM, over RDP, inside that cap.
  Possible (see `CUSTOM-ISO.md`) but a bad trade.

---

## 5. Deliberately not doing

- **Fan-made / pre-activated Windows ISOs.** Licensing and trust. The licensed
  image plus targeted customisation gets the same result without either problem.
- **A browser-streamed desktop** (Selkies/KasmVNC/neko). It is the better
  technology on paper, but it means a browser tab instead of the Windows App,
  and the Windows App is what has actually felt smooth here.

---

## The short version

Three things stand between "it works" and "it's the best it can be": **get the
two files in and Pages enabled**, **prove the backups really capture the Chrome
profile and the profile hive**, and **add a shared Drive folder so files can
move between your phone and the desktops**. Everything after that is polish.
