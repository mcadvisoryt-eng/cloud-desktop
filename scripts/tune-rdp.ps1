# tune-rdp.ps1 — remove every source of *added* RDP latency on a Windows runner.
# Idempotent: safe to run more than once. See WINDOWS.md for what each key does
# and for the client-side settings that matter just as much.
$ErrorActionPreference = 'Stop'

function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        $Value,
        [string]$Type = 'DWord'
    )
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

# ---- Transports: allow UDP, which is far lower latency than TCP ----------
$tsPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
Set-Reg $tsPol 'SelectTransport' 0      # 0 = use both UDP and TCP (UDP preferred)
Set-Reg $tsPol 'MaxBandwidth' 0         # no bandwidth cap / throttling
Set-Reg $tsPol 'KeepAliveInterval' 1    # don't drop a quiet session

# ---- Listener: minimum crypto (the Tailscale link already encrypts) -----
$rdp = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
Set-Reg $rdp 'MinEncryptionLevel' 1     # 1 = Low (2=ClientCompatible, 3=High, 4=FIPS)
Set-Reg $rdp 'SecurityLayer' 1          # 1 = Negotiate (keeps every client happy)
Set-Reg $rdp 'ColorDepth' 4             # 4 = 24-bit cap; clients may go lower

# ---- Desktop: no animations, effects or transparency --------------------
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
Set-Reg 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '0' String
Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' String
Set-Reg 'HKCU:\Control Panel\Desktop' 'ScreenSaveActive' '0' String
Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' String
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0

# ---- Never blank the screen or sleep ------------------------------------
foreach ($t in 'monitor-timeout-ac', 'standby-timeout-ac', 'disk-timeout-ac', 'monitor-timeout-dc', 'standby-timeout-dc') {
    powercfg /change $t 0 | Out-Null
}

Write-Host "RDP + desktop tuned for lowest added latency."
