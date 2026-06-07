#!/bin/bash
# scripts/04_wait_for_winrm.sh
# -----------------------------
# Polls the Windows EC2 instance until WinRM port 5985 is open.
# Called from the GitHub Actions workflow after Terraform apply.
#
# Usage:
#   ./scripts/04_wait_for_winrm.sh <public_ip> [max_wait_seconds]
#
# Example:
#   ./scripts/04_wait_for_winrm.sh 13.210.45.67 600

set -euo pipefail

TARGET_IP="${1:-}"
MAX_WAIT="${2:-600}"   # Default 10 minutes
WINRM_PORT=5985
INTERVAL=15

if [ -z "$TARGET_IP" ]; then
  echo "ERROR: No IP address provided."
  echo "Usage: $0 <ip_address> [max_seconds]"
  exit 1
fi

echo "==> Waiting for WinRM on $TARGET_IP:$WINRM_PORT (max ${MAX_WAIT}s)..."
ELAPSED=0

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  if nc -z -w 5 "$TARGET_IP" "$WINRM_PORT" 2>/dev/null; then
    echo "   WinRM is UP after ${ELAPSED}s ✓"
    exit 0
  fi

  echo "   [${ELAPSED}s] WinRM not ready yet — retrying in ${INTERVAL}s..."
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: WinRM did not become available within ${MAX_WAIT}s."
exit 1
