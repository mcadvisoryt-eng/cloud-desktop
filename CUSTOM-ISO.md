# Custom / modified Windows images

Short answer: **you cannot replace the runner's operating system.** On
GitHub-hosted runners the OS *is* the runner — GitHub hands you a VM built from
its own image and you cannot swap it out. So "custom Windows" means one of two
things, and only one of them is worth doing.

---

## Route A — customise the licensed image (recommended, and what this repo does)

This is the honest version of "a better Windows", and it needs **no ISO at all**.

The runner is `windows-latest` = **Windows Server 2025**, fully licensed and
activated by GitHub, with no expiry. It is not a trial. It feels stripped
because it is the *Server* SKU: no Microsoft Store, no consumer Start menu, no
modern apps.

`windows-desktop.yml` already customises it:

- **IST clock** — `Set-TimeZone -Id 'India Standard Time'`
- **Server annoyances off** — IE Enhanced Security Configuration disabled (it
  silently blocks ordinary browsing), Server Manager no longer opens at logon,
  telemetry services disabled, hibernation off
- **Aesthetic** — dark theme and a wallpaper generated on the runner with
  `System.Drawing` (so there is no licensing question about the image), applied
  to the **default profile** so `pc` inherits it on first logon
- **Shell** — Open-Shell Start menu
- **Apps** — Chrome (with Proton VPN, uBlock Origin, Bitwarden, Dark Reader,
  SponsorBlock force-installed), 7-Zip, Notepad++, VLC, Discord, Spotify

To add more, edit the `Customise the desktop` step. Any Chocolatey package
works:

```powershell
foreach ($pkg in 'firefox','vlc','obs-studio') {
  choco install $pkg -y --no-progress
}
```

**Script-based debloat playbooks** are also legitimate here: AtlasOS and ReviOS
distribute *playbooks that modify a licensed Windows install*, not redistributed
ISOs. Applying one to the runner is the same category as the step above.

---

## Route B — a real custom ISO, inside a nested VM

Technically possible, genuinely worse, and only legitimate with a **licensed**
image. Here is the whole picture.

### How it would work

Windows runners expose nested virtualisation, so you can run Hyper-V inside the
runner and boot your own ISO in a VM:

```powershell
# 1. Hyper-V + a NAT switch so the VM can reach the tailnet
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
New-VMSwitch -Name 'NestedNat' -SwitchType Internal
$if = Get-NetAdapter | Where-Object Name -eq 'vEthernet (NestedNat)'
New-NetIPAddress -IPAddress 172.20.0.1 -PrefixLength 24 -InterfaceIndex $if.ifIndex
New-NetNat -Name 'NestedNat' -InternalIPInterfaceAddressPrefix 172.20.0.0/24

# 2. Create the VM and attach the ISO
New-VM -Name custom -MemoryStartupBytes 8GB -NewVHDPath C:\vm\custom.vhdx -NewVHDSizeBytes 60GB -SwitchName 'NestedNat'
Add-VMDvdDrive -VMName custom -Path C:\iso\custom.iso
Set-VMFirmware -VMName custom -FirstBootDevice (Get-VMDvdDrive -VMName custom)

# 3. Boot it (unattended install, then RDP into 172.20.0.x:3389)
Start-VM -Name custom
```

Then you RDP into the **VM's** address rather than the runner's, and forward it
over Tailscale (`tailscale up` inside the VM, or a port proxy on the host).

### Where the ISO lives

**Not in this repo.** It is public, and an ISO is 4–6 GB. Put it somewhere the
runner can download and treat it as a build input:

- a **GitHub Release asset** in this repo (best: versioned, downloadable),
- your Google Drive, fetched with the existing `RCLONE_CONFIG` secret,
- any HTTPS URL.

Then `Invoke-WebRequest -Uri $ISO_URL -OutFile C:\iso\custom.iso`.

### Why it is a bad trade

- **Slower.** A VM inside a VM, over RDP, inside a 6-hour cap. Everything is
  one more layer of virtualisation.
- **Still ephemeral.** The VM disk dies with the runner unless you back it up
  to the encrypted Drive remote — a 60 GB VHDX, every session.
- **Activation.** A modified image still needs to be activated legitimately.
  "Pre-activated" builds are pirated, and not something this repo will help
  with.
- **Trust.** Fan-made ISOs (Tiny11, AtlasOS forks, Ghost Spectre and similar)
  come from unofficial sources and have a history of bundled tooling that is
  itself questionable. On a box where you sign into Proton and Bitwarden, that
  is a bad bet.

---

## The line this repo does not cross

- A **licensed** Windows ISO (Microsoft, or an image you are entitled to) in a
  VM: fine.
- A **script/playbook** that modifies a licensed install: fine.
- **Pre-activated / cracked / "no-activation" ISOs**: not something I will help
  set up. If you supply a legitimately licensed image, Route B above is a
  mechanical exercise.

---

## Recommendation

Stay on Route A. It gives you the smooth, dark, app-equipped Windows you asked
for, on a licensed image, with none of the performance, licensing or trust
problems. If a specific thing is missing — a Store app, a particular look — say
which one and it can almost always be installed or configured directly.
