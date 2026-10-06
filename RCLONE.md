# RCLONE — full setup for the `RCLONE_CONFIG` secret

`RCLONE_CONFIG` is the whole contents of an rclone config file that defines two
remotes:

- **`backup:`** — your actual cloud storage (Google Drive, OneDrive, Dropbox, S3 …)
- **`crypt:`** — an encrypted *view* of a folder inside `backup:`

The workflows only ever touch the encrypted view: `crypt:home` (Linux profile),
`crypt:winhome` (Windows profile) and `crypt:trash` (7-day recoverable
deletions). Because `crypt:` sits in front, your cloud provider only ever stores
ciphertext — they never see your files in the clear.

This secret is **optional**. Without it, every session starts with a blank
profile (no persistence). With it, your home directory survives across sessions
and across runners.

---

## 0. Install rclone on your own computer

Do this on your laptop/desktop — **not** on the runner.

- **Windows:** `winget install Rclone.Rclone` (or download from <https://rclone.org/downloads/>)
- **macOS:** `brew install rclone`
- **Linux:** `sudo apt install rclone` or `curl https://rclone.org/install.sh | sudo bash`

Check it works: `rclone version`

---

## 1. Create the storage remote (`backup:`)

Run `rclone config`. It opens an interactive menu.

```
n) New remote
name> backup
Storage> drive          # Google Drive. Use onedrive, dropbox, s3, etc. as you like
```

For **Google Drive**, the prompts go:

```
client_id>              # leave blank (press Enter)
client_secret>          # leave blank
scope> 1                # 1 = full access
root_folder_id>        # blank
service_account_file>  # blank
Edit advanced config?  n
Use auto config?       y     # opens your browser to authorize
```

A browser window opens — sign in and click **Allow**. Back in the terminal:

```
Configure this as a Shared Drive (Team Drive)?  n
Keep this "backup" remote?  y
```

You're back at the menu. Type **`q`** to quit for now.

> **Headless / server?** If you're setting this up on a machine with no browser,
> run `rclone authorize "drive"` on a machine that *does* have one, then paste
> the resulting token when asked.

---

## 2. Create the crypt remote (`crypt:`)

Run `rclone config` again.

```
n) New remote
name> crypt
Storage> crypt          # "Encrypt/Decrypt a remote"
remote> backup:cloud-desktop
```

`backup:cloud-desktop` is the folder (on your storage) where the encrypted data
will live — the folder doesn't need to exist yet; rclone creates it.

```
filename_encryption> standard
directory_name_encryption> true
password>               # press g to generate a strong one, or type your own
password2 (salt)>       # press g to generate one
```

> ### ⚠️ Save the password and salt somewhere safe, right now.
> They're stored (obfuscated) in the config file, but **if you ever lose them
> you cannot decrypt your backups — not even rclone support can help.** Put them
> in your password manager before moving on.

```
Keep this "crypt" remote?  y
q                        # quit
```

---

## 3. Verify it works

```bash
rclone lsd crypt:
```

No error (even if it lists nothing, because it's empty) means the pair is set up
correctly. To prove write/read end-to-end:

```bash
echo hello | rclone rcat crypt:test.txt
rclone cat crypt:test.txt      # prints: hello
rclone delete crypt:test.txt
```

---

## 4. Copy the config file

```bash
# Linux / macOS
cat ~/.config/rclone/rclone.conf

# Windows (PowerShell)
Get-Content "$env:APPDATA\rclone\rclone.conf"

# Windows (cmd)
type %APPDATA%\rclone\rclone.conf
```

It looks like this (values obfuscated here):

```ini
[backup]
type = drive
scope = drive
token = {"access_token":"ya29....","token_type":"Bearer","refresh_token":"1//....","expiry":"2026-01-01T00:00:00.000000000Z"}

[crypt]
type = crypt
remote = backup:cloud-desktop
filename_encryption = standard
directory_name_encryption = true
password = aBcDeF...obfuscated...
password2 = zYxWvU...obfuscated...
```

Copy the **entire file**, both sections, exactly as-is.

---

## 5. Add it as the `RCLONE_CONFIG` secret

**Settings → Secrets and variables → Actions → New repository secret**, name
`RCLONE_CONFIG`, and paste the whole file contents as the value.

Or do it from the terminal without pasting into a browser (reads hidden, never
writes to disk):

```bash
gh auth login
./scripts/set-secrets.sh <owner>/<repo>     # choose the RCLONE_CONFIG prompt
```

---

## Notes & gotchas

- **The remote must be named `crypt`** and point at a `backup:`-prefixed path —
  the workflows reference `crypt:home`, `crypt:winhome` and `crypt:trash`.
- **Treat the file as highly sensitive.** It contains your OAuth refresh token
  *and* your crypt password/salt. It belongs in a secret, never in a file in the
  repo.
- **Don't change the crypt password or salt later** — doing so makes every
  existing backup unreadable.
- **Google Drive OAuth tokens** refresh automatically as long as the refresh
  token is present; if you ever revoke access in your Google account, re-run
  step 1.
- **Which folder does it use?** With `remote = backup:cloud-desktop`, your Linux
  home lands at `cloud-desktop/home/…` on your storage, Windows at
  `cloud-desktop/winhome/…`, deleted files at `cloud-desktop/trash/<timestamp>/…`.
- **On the cloud VM** (`CLOUD-VM.md`) you don't use a GitHub secret — you drop
  the same file at `~/.config/rclone/rclone.conf` on the VM.
- **Skip this entirely** if you don't need persistence; the desktops still work,
  they just start fresh each session.
