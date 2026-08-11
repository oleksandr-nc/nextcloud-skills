#!/bin/sh
# SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Preflight for ExApp development on macOS: has your machine answer the questions the
# runbook can only describe. Reports the Docker socket to configure, whether amd64
# emulation works, whether host.docker.internal resolves, whether ports 80/443 are
# free, and how much memory the engine's VM has.
#
# Usage:  sh macos-preflight.sh
#
# Changes nothing. Runs a few throwaway containers from a small image (alpine).
# Exit code 0 when nothing blocking was found, 1 otherwise.

set -u

PROBE_IMAGE=${PROBE_IMAGE:-alpine}
fails=0
warns=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  OK    %s\n' "$1"; }
warn() { printf '  WARN  %s\n' "$1"; warns=$((warns + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
note() { printf '        %s\n' "$1"; }

section "Host"
os=$(uname -s)
arch=$(uname -m)
printf '  %s %s (%s)\n' "$os" "$(uname -r)" "$arch"
if [ "$os" != "Darwin" ]; then
    warn "this script is written for macOS; on Linux use the runbook directly"
fi

section "Container engine"
if ! command -v docker >/dev/null 2>&1; then
    bad "no docker CLI in PATH; install Docker Desktop, OrbStack, Colima or Rancher Desktop"
    printf '\n%s failure(s), %s warning(s)\n' "$fails" "$warns"
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    bad "docker CLI present but the engine is not reachable; start it and re-run"
    printf '\n%s failure(s), %s warning(s)\n' "$fails" "$warns"
    exit 1
fi
engine=$(docker info --format '{{.ServerVersion}} {{.OSType}}/{{.Architecture}}' 2>/dev/null)
ncpu=$(docker info --format '{{.NCPU}}' 2>/dev/null)
mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null)
ok "engine $engine"
note "VM resources: ${ncpu} CPUs, $((mem_bytes / 1024 / 1024 / 1024)) GB RAM"
if [ "${mem_bytes:-0}" -lt 8000000000 ]; then
    warn "less than 8 GB for the engine VM; raise it in your engine's settings"
    note "Nextcloud plus HaRP plus one ExApp is tight below 8 GB, AI ExApps need much more"
fi

section "Docker socket (HaRP must bind-mount it)"
sock_uri=$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || echo '')
sock_path=""
case "$sock_uri" in
    unix://*) sock_path=${sock_uri#unix://} ;;
esac
if [ -z "$sock_path" ]; then
    for candidate in \
        /var/run/docker.sock \
        "${HOME:-}/.docker/run/docker.sock" \
        "${HOME:-}/.orbstack/run/docker.sock" \
        "${HOME:-}/.colima/default/docker.sock" \
        "${HOME:-}/.rd/docker.sock"
    do
        [ -S "$candidate" ] && { sock_path=$candidate; break; }
    done
fi

if [ -n "$sock_path" ] && [ -S "$sock_path" ]; then
    ok "socket at $sock_path"
    if [ "$sock_path" = "/var/run/docker.sock" ]; then
        note "this is the default, so DOCKER_SOCKET does not need to be set"
        env_socket=""
    else
        env_socket="DOCKER_SOCKET=$sock_path"
        note "not the default path, so it must be configured (see the summary below)"
    fi
else
    bad "no usable unix socket found (context reports '${sock_uri:-none}')"
    note "Docker Desktop: enable the default Docker socket in Settings > Advanced,"
    note "or point DOCKER_SOCKET at the path your engine uses"
    env_socket=""
fi

section "Architecture and emulation"
if [ "$arch" = "arm64" ] || [ "$arch" = "aarch64" ]; then
    note "Apple Silicon: the dev environment, HaRP, test-deploy and the reference ExApp are arm64-native"
    if docker run --rm --platform linux/amd64 "$PROBE_IMAGE" uname -m >/dev/null 2>&1; then
        ok "amd64 emulation works, so amd64-only images can run (slowly)"
        note "llm2 and context_chat_backend are amd64-only; emulated inference is not usable in practice"
        note "run those on a remote amd64 host instead (see remote-daemon.md)"
    else
        warn "amd64 emulation does not work; amd64-only images will not run at all"
        note "Docker Desktop: enable Rosetta for x86/amd64 emulation in Settings > General"
    fi
else
    ok "amd64 host: no emulation needed for any published ExApp image"
fi

section "host.docker.internal (the manual-install loop needs it)"
if docker run --rm "$PROBE_IMAGE" getent hosts host.docker.internal >/dev/null 2>&1; then
    ok "resolves from inside a container"
else
    warn "does not resolve from inside a container"
    note "the manual_dev daemon reaches your locally running ExApp through this name"
    note "on engines without it, add: --add-host host.docker.internal:host-gateway"
fi

section "Ports for the proxy"
for port in 80 443; do
    if docker run --rm -p "127.0.0.1:${port}:${port}" "$PROBE_IMAGE" true >/dev/null 2>&1; then
        ok "port $port is free"
    else
        warn "port $port is in use; stop whatever holds it or change the bind in .env"
    fi
done

section "Summary: .env lines for this machine"
printf '  PROTOCOL=http\n'
printf '  DOMAIN_SUFFIX=.test          # not .local: that is mDNS territory on macOS\n'
[ -n "${env_socket:-}" ] && printf '  %s\n' "$env_socket"
printf '\n  Then follow dev-environment.md, replacing nextcloud.local with nextcloud.test.\n'

printf '\n%s failure(s), %s warning(s)\n' "$fails" "$warns"
[ "$fails" -eq 0 ] || exit 1
exit 0
