#!/usr/bin/env bash
# Mobile Messenger - one-command backend startup.
#
# Why this fixes the "networking breaks after every restart" problem:
#
# Running the backend directly inside WSL2 (e.g. `mvnw spring-boot:run`)
# only binds to WSL2's own private, NAT'd network. WSL2's internal IP
# address is not stable - it can (and typically does) change after a
# Windows/WSL restart - so making the backend reachable from a physical
# phone on the same Wi-Fi/hotspot network required a Windows-side port
# forward (`netsh interface portproxy`) pointed at that IP, which had to be
# manually re-created every time the IP changed.
#
# Docker Desktop does not have this problem: it publishes a container's
# port directly on the Windows host's own network interfaces (confirmed:
# `docker compose`'s published port 8080 is reachable at the Windows
# machine's real Wi-Fi IP with zero portproxy/firewall setup beyond what
# Docker Desktop itself already configures on install). Using Docker
# Compose as the one and only way this script starts the backend means
# there is no WSL IP to track, and nothing to reconfigure after a restart -
# whatever this script prints below (the Windows host's current LAN IP) is
# simply read live each run, never hardcoded.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

echo "Mobile Messenger - starting backend"
echo

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: 'docker' was not found on PATH." >&2
  echo "Install Docker Desktop (with WSL integration enabled for this distro, if on WSL)," >&2
  echo "then re-run ./start.sh." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is installed but its engine is not running." >&2
  echo "Start Docker Desktop, wait until it says it's running, then re-run ./start.sh." >&2
  exit 1
fi

echo "Starting PostgreSQL + backend containers (docker compose up --build -d)..."
docker compose up --build -d

BACKEND_URL="http://localhost:8080"
HEALTH_URL="$BACKEND_URL/api/health"

echo
echo "Waiting for the backend to become healthy..."
ready=false
for i in $(seq 1 30); do
  if curl -sf "$HEALTH_URL" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done

if [ "$ready" != true ]; then
  echo "ERROR: the backend did not become healthy within 60 seconds." >&2
  echo "Check what went wrong with: docker compose logs backend" >&2
  exit 1
fi

echo "Backend is healthy."
echo
echo "=================================================================="
echo " Backend URL (this machine):        $BACKEND_URL"
echo " Android emulator should use:       http://10.0.2.2:8080"
echo "   (the Flutter app already defaults to this automatically on the"
echo "    emulator - no --dart-define needed)"

# Best-effort only: report the Windows host's current LAN-facing IP, purely
# as information for testing on a physical phone on the same Wi-Fi/hotspot
# network. This is read fresh every run - nothing here is hardcoded, and
# nothing needs to be reconfigured if it changes between restarts, because
# Docker Desktop (not this script) is what makes that address reachable.
if command -v powershell.exe >/dev/null 2>&1; then
  HOST_IP=$(powershell.exe -NoProfile -Command \
    "(Get-NetIPConfiguration | Where-Object { \$_.IPv4DefaultGateway -and \$_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1 -ExpandProperty IPv4Address).IPAddress" \
    2>/dev/null | tr -d '\r\n')
  if [ -n "${HOST_IP:-}" ]; then
    echo " Physical Android device (same Wi-Fi/hotspot) should use: http://$HOST_IP:8080"
    echo "   Build the APK with:"
    echo "     cd mobile_messenger && flutter build apk --release --dart-define=API_BASE_URL=http://$HOST_IP:8080"
  else
    echo " Could not auto-detect this machine's LAN IP for physical-device testing."
    echo " Find it yourself (e.g. 'ipconfig' on Windows, look for the Wi-Fi adapter's IPv4 address)"
    echo " and build with: flutter build apk --release --dart-define=API_BASE_URL=http://<that-ip>:8080"
  fi
fi
echo "=================================================================="
