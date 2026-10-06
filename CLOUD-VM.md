# Cloud VM in an Indian region — the low-latency option

This is the path that actually reaches the latency you asked for. Everything
else in this repo runs on GitHub Actions, whose runners sit in Azure in a region
**you cannot choose** — usually the US. From India that's ~180–250 ms of pure
network travel. A VM in an Indian region cuts that to **~5–30 ms**, and gives
you a persistent disk and no 6-hour cap at the same time.

Run it in one of these regions and the desktop feels local:

| Provider | Indian region(s) | Notes |
|---|---|---|
| **Oracle Cloud (OCI)** | Mumbai `ap-mumbai-1`, Hyderabad `ap-hyderabad-1` | **Always Free**: 4 ARM Ampere cores + 24 GB RAM, free forever. Best free option, and available in India. |
| AWS | `ap-south-1` Mumbai, `ap-south-2` Hyderabad | 12-month free tier (`t3.micro`) |
| Azure | Central India (Pune), South India (Chennai) | 12-month free tier (`B1s`) |
| DigitalOcean | Bangalore `blr1` | from ~$6/mo (1 GB) |
| Linode / Akamai | Mumbai, Chennai | from ~$5/mo |
| Vultr | Mumbai, Bangalore, Delhi NCR | from ~$6/mo |
| E2E Networks | Delhi / Mumbai | Indian provider, billed in ₹ |

> Prices and free-tier terms change — check the provider before you commit.
> Pick the region physically closest to you; 500 km closer is a real
> millisecond win.

---

## Option A — Linux desktop (Ubuntu + XFCE + xrdp)

This reuses the exact tuning from the Actions workflow (`tune-xrdp.py`).

1. Create an Ubuntu 22.04 or 24.04 VM in an Indian region. **Open no inbound
   ports** — Tailscale is the only door in.
2. Copy this repo onto the VM (or just the `scripts/` folder).
3. Run the provisioner:

   ```bash
   sudo DESKTOP_PASSWORD='YourPass1' \
        TS_AUTHKEY='tskey-auth-...' \
        ./scripts/provision-cloudvm.sh
   ```

   It installs XFCE + xrdp, applies the latency tuning, and brings up
   Tailscale. Override the user with `DESKTOP_USER=...` (default `pc`).
4. From a device on your tailnet, RDP to `<TS_HOSTNAME>.<tailnet>.ts.net:3389`
   (default host `cloudpc`), user `pc`, password `DESKTOP_PASSWORD`.

## Option B — Windows desktop

Pick a **Windows Server 2022** image from the same provider.

1. Create the VM, set an admin password, and connect once via the provider's
   console (or RDP over the public IP if you allow it temporarily).
2. Install Tailscale from <https://tailscale.com/download> and run
   `tailscale up --hostname=cloudpc-win`. Then close the public RDP port.
3. Copy `scripts/tune-rdp.ps1` over and run it in an elevated PowerShell to
   apply the same low-latency RDP settings the Actions workflow uses.

## Why bother, vs the Actions version

| | GitHub Actions runner | Cloud VM in India |
|---|---|---|
| RTT from India | ~180–250 ms | **~5–30 ms** |
| Session length | 6 h hard cap, then a handoff gap | runs until you stop it |
| Persistence | snapshot/restore to rclone | real disk, always there |
| Cost | free (public repo) | free tier, or ~$5–25/mo |
| Setup | zero — push and go | you manage the VM |

If latency is the point, this table is the whole argument.

---

## Secrets for the cloud VM

The GitHub Actions secrets do **not** apply here — a VM uses its own
credentials. You need:

- **`DESKTOP_PASSWORD`** — the RDP/login password (choose one).
- **`TS_AUTHKEY`** — a Tailscale auth key (same kind as the workflows use).
- **An SSH key pair** — for `ssh ubuntu@<vm-ip>` while you set it up. Generate
  with `ssh-keygen -t ed25519`, paste the public half into the provider's
  "SSH key" field when creating the VM. Never share the private half.

See `SECRETS.md` for exactly how to obtain the Tailscale key.
