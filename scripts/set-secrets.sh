#!/usr/bin/env bash
# Set the four cloud-desktop repository secrets with the GitHub CLI.
#
# Secrets are read interactively (hidden) and piped straight into
# `gh secret set`, so they are NEVER written to disk, never land in your shell
# history, and never get committed. GitHub stores them encrypted and injects
# them into workflow runs only.
#
# Usage:   ./scripts/set-secrets.sh <owner/repo>
# Needs:   gh installed and authenticated  (gh auth login)
set -euo pipefail

REPO="${1:?usage: set-secrets.sh <owner/repo>   e.g. vot1122/cloud-desktop}"

set_secret() {
  local name="$1" hint="$2" val
  read -rsp "${name} — ${hint}: " val
  echo
  printf '%s' "$val" | gh secret set "$name" --repo "$REPO"
  unset val
}

set_secret DESKTOP_PASSWORD "the RDP password you will type (username is pc)"
set_secret RESTART_PAT      "fine-grained PAT with Actions: read+write"
set_secret TS_AUTHKEY       "Tailscale auth key (tskey-auth-...), reusable + ephemeral"

echo "RCLONE_CONFIG — paste the full rclone.conf (end with Ctrl-D):"
gh secret set RCLONE_CONFIG --repo "$REPO"

echo
echo "Secrets now set on ${REPO}:"
gh secret list --repo "$REPO"
