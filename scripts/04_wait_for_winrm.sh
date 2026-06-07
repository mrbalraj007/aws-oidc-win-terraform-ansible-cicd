#!/bin/bash
# scripts/04_wait_for_winrm.sh
# -----------------------------
# Polls the Windows EC2 instance until WinRM is both:
#   1. Port 5985 is open (TCP)
#   2. ansible_admin user can authenticate via WinRM
#
# Called from the GitHub Actions workflow after Terraform apply.
#
# Usage:
#   ./scripts/04_wait_for_winrm.sh <public_ip> [max_wait_seconds] [ansible_password]
#
# Example:
#   ./scripts/04_wait_for_winrm.sh 13.210.45.67 300 MyS0cureP0ss2026

set -euo pipefail

TARGET_IP="${1:-}"
MAX_WAIT="${2:-300}"
ANSIBLE_PASSWORD="${3:-${TF_VAR_ansible_windows_password:-}}"
WINRM_PORT=5985
INTERVAL=15

if [ -z "$TARGET_IP" ]; then
  echo "ERROR: No IP address provided."
  echo "Usage: $0 <ip_address> [max_seconds] [ansible_password]"
  exit 1
fi

if [ -z "$ANSIBLE_PASSWORD" ]; then
  echo "ERROR: No Ansible password provided (arg 3 or TF_VAR_ansible_windows_password env var)."
  exit 1
fi

echo "==> Waiting for WinRM + ansible_admin auth on $TARGET_IP:$WINRM_PORT (max ${MAX_WAIT}s)..."
ELAPSED=0

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  # 1. Check TCP port is open
  if ! nc -z -w 5 "$TARGET_IP" "$WINRM_PORT" 2>/dev/null; then
    echo "   [${ELAPSED}s] Port $WINRM_PORT not open yet — retrying in ${INTERVAL}s..."
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
    continue
  fi

  # 2. Try WinRM authentication with ansible_admin user
  # Uses PowerShell on the CI runner to run a WinRM quickconfig test
  AUTH_RESULT=$(python3 -c "
import winrm
try:
    sess = winrm.Session('$TARGET_IP', auth=('ansible_admin', '$ANSIBLE_PASSWORD'))
    sess.run_cmd('echo test')
    print('OK')
except Exception as e:
    print(f'FAIL: {e}')
" 2>&1 || true)

  if echo "$AUTH_RESULT" | grep -q "^OK$"; then
    echo "   WinRM auth SUCCESS for ansible_admin after ${ELAPSED}s ✓"
    exit 0
  else
    echo "   [${ELAPSED}s] WinRM port open but ansible_admin auth failed — retrying in ${INTERVAL}s..."
    echo "   (WinRM may still be configuring via userdata...)"
  fi

  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "ERROR: WinRM+auth did not become available within ${MAX_WAIT}s."
echo "Last auth attempt result: $AUTH_RESULT"
exit 1