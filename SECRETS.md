# SECRETS — what to add and how to get each value

Add these under **Settings → Secrets and variables → Actions → New repository
secret**. A public repo does **not** expose secrets: they're stored encrypted,
outside the repo, and masked in logs. Never commit a value as a file.

Set them all in one go with the helper (values are read hidden, never written
to disk):

```bash
gh auth login
./scripts/set-secrets.sh <owner>/<repo>
```

---

## 1. `TS_AUTHKEY` — required

The Tailscale auth key. GitHub runners have no open inbound ports, so this is
the only way you can reach the desktop.

1. Sign up free at <https://tailscale.com> and install Tailscale on the device
   you'll connect from; log in once.
2. Admin console → **Settings → Keys → Generate auth key**.
3. Set **Reusable: yes** and **Ephemeral: yes** (dead runners disappear from
   your tailnet automatically).
4. Copy the key — it looks like `tskey-auth-xxxxxxxxxxxx`.
5. Note the expiry (max 90 days); regenerate when it lapses.

## 2. `DESKTOP_PASSWORD` — required

The RDP login password. Choose it yourself — it's not fetched from anywhere.

- Username is `pc` (Linux) or `runneradmin` (Windows).
- Windows enforces complexity: **8+ characters with upper case, lower case and
  a digit**. Example shape: `Blu3-Door!7`.

## 3. `RESTART_PAT` — optional

Lets a session chain the next one past GitHub's 6-hour cap. Without it, the
desktop stops after 6 h and you restart it manually.

1. GitHub → your avatar → **Settings → Developer settings → Personal access
   tokens → Fine-grained tokens → Generate new token**.
2. **Repository access:** Only select repositories → this repo.
3. **Permissions:** *Actions → Read and write*.
4. Copy the token — it looks like `github_pat_xxxxxxxx`.
5. Note the expiry; when it lapses the chain stops until you replace it.

## 4. `RCLONE_CONFIG` — optional

Encrypted backup of your home directory, so the desktop persists across
sessions. Without it every session starts with a blank profile.

**Full step-by-step walkthrough: see `RCLONE.md`.** The short version, done once
on your own computer (install rclone from <https://rclone.org>):

```bash
rclone config
# n) new remote, name: backup
#     Storage: Google Drive (or Dropbox, OneDrive, S3 …)
#     Follow the browser OAuth flow.
#
# n) new remote, name: crypt
#     Storage: Encrypt/Decrypt a remote
#     remote to encrypt: backup:cloud-desktop
#     filename encryption: standard
#     directory name encryption: true
#     password + salt: let it generate — KEEP THEM SAFE (they're in the file)
```

Then copy the whole file's contents as the secret value:

```bash
cat ~/.config/rclone/rclone.conf
```

---

## Cloud VM (not a GitHub secret)

If you go the Indian-region VM route (`CLOUD-VM.md`), the secrets above don't
apply. You instead need:

| Thing | Where to get it |
|---|---|
| `DESKTOP_PASSWORD` | you choose it |
| `TS_AUTHKEY` | exactly as in step 1 above |
| SSH key pair | `ssh-keygen -t ed25519` — paste the **public** half into the provider's SSH-key field; keep the private half secret |

---

## Quick checklist

| Secret | Required? | Value source |
|---|---|---|
| `TS_AUTHKEY` | **Yes** | Tailscale admin → Settings → Keys |
| `DESKTOP_PASSWORD` | **Yes** | you choose |
| `RESTART_PAT` | Optional | GitHub → Developer settings → Fine-grained tokens |
| `RCLONE_CONFIG` | Optional | `rclone config` output |
