#!/usr/bin/env sh

set -eu

if ! command -v pwsh >/dev/null 2>&1; then
  echo 'PowerShell 7 (pwsh) is required to run the Azure Automation post-provision steps on POSIX systems.' >&2
  exit 1
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec pwsh -NoProfile -NonInteractive -File "$SCRIPT_DIR/postprovision.ps1"
