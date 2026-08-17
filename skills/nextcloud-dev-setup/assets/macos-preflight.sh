#!/bin/sh
# SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Preflight for ExApp development on macOS: has your machine answer the questions the
# runbook can only describe. Reports the Docker socket to configure (and whether a
# container can actually use it), whether amd64 emulation works, whether
# host.docker.internal resolves, whether ports 80/443 are free, and the CPU, memory and
# disk the engine's VM has.
#
# Usage:  sh macos-preflight.sh
#
# Changes nothing on your system or in your engine's settings. It does pull a small probe
# image (alpine:3.21, the same base the reference ExApp uses) and run throwaway containers
# from it.  Exit code 0 when nothing blocking was found, 1 otherwise.

set -u

PROBE_IMAGE=${PROBE_IMAGE:-alpine:3.21}
fails=0
warns=0

section() { printf '\n=== %s ===\n' "$1"; }
ok()   { printf '  OK    %s\n' "$1"; }
warn() { printf '  WARN  %s\n' "$1"; warns=$((warns + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
note() { printf '        %s\n' "$1"; }

# Bytes -> GiB with one decimal, without relying on floating point.
gib() { printf '%s.%s' "$(($1 / 1073741824))" "$(( ($1 % 1073741824) * 10 / 1073741824 ))"; }

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

if docker compose version >/dev/null 2>&1; then
    ok "docker compose $(docker compose version --short 2>/dev/null)"
else
    bad "docker compose v2 is missing; the runbook is written against 'docker compose', not 'docker-compose'"
fi

# Every probe below pins the platform explicitly. Without that, the amd64 emulation probe
# leaves the probe image's tag pointing at its amd64 variant on engines that keep one image
# per tag, and every later probe then runs emulated - or fails outright when emulation is
# unavailable, reporting problems that do not exist.
docker_arch=$(docker info --format '{{.Architecture}}' 2>/dev/null)
case "$docker_arch" in
    aarch64|arm64) native_platform=linux/arm64 ;;
    x86_64|amd64)  native_platform=linux/amd64 ;;
    *)             native_platform="" ;;
esac
platform_arg=""
[ -n "$native_platform" ] && platform_arg="--platform $native_platform"

if ! docker image inspect "$PROBE_IMAGE" >/dev/null 2>&1; then
    note "pulling the probe image $PROBE_IMAGE"
fi
# shellcheck disable=SC2086
if ! docker pull -q $platform_arg "$PROBE_IMAGE" >/dev/null 2>&1; then
    bad "cannot pull the probe image $PROBE_IMAGE; check network and registry access"
    printf '\n%s failure(s), %s warning(s)\n' "$fails" "$warns"
    exit 1
fi

section "Engine VM resources"
if [ -n "${mem_bytes:-}" ] && [ "${mem_bytes:-0}" -gt 0 ] 2>/dev/null; then
    printf '  %s CPUs, %s GiB RAM\n' "${ncpu:-?}" "$(gib "$mem_bytes")"
    # 7.5 GiB, i.e. what an engine configured for "8 GB" typically reports after VM overhead.
    if [ "$mem_bytes" -lt 8053063680 ]; then
        warn "the engine VM has $(gib "$mem_bytes") GiB; the runbook asks for 8 GB or more"
        note "Nextcloud plus HaRP plus one ExApp is tight below that, AI ExApps need much more"
        note "raise it in your engine's resource settings"
    fi
else
    warn "could not read the engine's memory from docker info"
fi
# shellcheck disable=SC2086
vm_free=$(docker run --rm $platform_arg "$PROBE_IMAGE" df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "${vm_free:-}" ]; then
    printf '  %s GiB free on the engine VM disk (images, volumes, ExApp containers)\n' "$(gib "$((vm_free * 1024))")"
    if [ "$vm_free" -lt 26214400 ]; then
        warn "under 25 GiB free in the VM; the dev images alone are around 3 GiB and AI images are far larger"
    fi
fi
host_free=$(df -Pk "$PWD" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "${host_free:-}" ]; then
    printf '  %s GiB free on this Mac (the bind-mounted source tree lives here)\n' "$(gib "$((host_free * 1024))")"
fi

section "Docker socket (HaRP must bind-mount it)"
# The requirement is not "a socket exists" but "a container can talk to the engine through
# a bind mount of it", which is what HaRP does. Probe exactly that.
socket_usable() {
    # shellcheck disable=SC2086
    docker run --rm $platform_arg -v "$1:/var/run/docker.sock" "$PROBE_IMAGE" \
        test -S /var/run/docker.sock >/dev/null 2>&1
}

sock_uri=$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || echo '')
ctx_sock=""
case "$sock_uri" in
    unix://*) ctx_sock=${sock_uri#unix://} ;;
esac

# /var/run/docker.sock first: when it works, .env needs no DOCKER_SOCKET at all. Docker
# Desktop creates it as a symlink when "Allow the default Docker socket to be used" is on.
sock_path=""
for candidate in \
    /var/run/docker.sock \
    "$ctx_sock" \
    "${HOME:-}/.docker/run/docker.sock" \
    "${HOME:-}/.orbstack/run/docker.sock" \
    "${HOME:-}/.colima/default/docker.sock" \
    "${HOME:-}/.rd/docker.sock"
do
    [ -n "$candidate" ] || continue
    [ -S "$candidate" ] || continue
    if socket_usable "$candidate"; then
        sock_path=$candidate
        break
    fi
    note "$candidate exists but a container cannot bind-mount it; trying the next candidate"
done

env_socket=""
if [ -n "$sock_path" ]; then
    ok "socket at $sock_path, usable from inside a container"
    if [ "$sock_path" = "/var/run/docker.sock" ]; then
        note "this is the default, so DOCKER_SOCKET does not need to be set"
    else
        env_socket="DOCKER_SOCKET=$sock_path"
        note "not the default path, so it must be configured (see the summary below)"
    fi
else
    bad "no bind-mountable unix socket found (context reports '${sock_uri:-none}')"
    note "Docker Desktop: enable the default Docker socket in Settings > Advanced,"
    note "or point DOCKER_SOCKET at the path your engine uses"
fi

section "Architecture and emulation"
if [ "$native_platform" = "linux/arm64" ]; then
    note "Apple Silicon: the dev environment, HaRP, test-deploy and the reference ExApp are arm64-native"
    if docker run --rm --platform linux/amd64 "$PROBE_IMAGE" true >/dev/null 2>&1; then
        ok "amd64 emulation works, so amd64-only images can run (slowly)"
        note "llm2 and context_chat_backend are amd64-only; emulated inference is not usable in practice"
        note "run those on a remote amd64 host instead (see remote-daemon.md)"
    else
        warn "amd64 emulation does not work; amd64-only images will not run at all"
        note "Docker Desktop: enable Rosetta for x86/amd64 emulation in Settings > General"
    fi
elif [ "$native_platform" = "linux/amd64" ]; then
    ok "amd64 host: no emulation needed for any published ExApp image"
else
    warn "unrecognised engine architecture '${docker_arch:-unknown}'; probes run without a platform pin"
fi

section "host.docker.internal (the manual-install loop needs it)"
# shellcheck disable=SC2086
if docker run --rm $platform_arg "$PROBE_IMAGE" getent hosts host.docker.internal >/dev/null 2>&1; then
    ok "resolves from inside a container"
else
    warn "does not resolve from inside a container"
    note "the manual_dev daemon reaches your locally running ExApp through this name"
    note "on engines without it, add: --add-host host.docker.internal:host-gateway"
fi

section "Ports for the proxy"
for port in 80 443; do
    # shellcheck disable=SC2086
    if docker run --rm $platform_arg -p "127.0.0.1:${port}:${port}" "$PROBE_IMAGE" true >/dev/null 2>&1; then
        ok "port $port is free"
    else
        warn "port $port is in use"
        note "expected if the nextcloud-docker-dev proxy is already running (docker compose ps proxy);"
        note "otherwise stop whatever holds it, or change PROXY_PORT_HTTP/PROXY_PORT_HTTPS in .env"
    fi
done

section "Summary: what this machine needs in .env"
if [ -n "$env_socket" ]; then
    printf '  Add one line to .env after running bootstrap.sh:\n\n'
    printf '      %s\n\n' "$env_socket"
    printf '  Everything else in dev-environment.md applies unchanged, including\n'
    printf '  DOMAIN_SUFFIX=.local (/etc/hosts entries short-circuit mDNS; see macos.md).\n'
else
    printf '  Nothing. bootstrap.sh writes a working .env for this machine as-is:\n'
    printf '  the default socket works, so DOCKER_SOCKET is not needed, and .local\n'
    printf '  resolves through /etc/hosts without touching mDNS.\n\n'
    printf '  Follow dev-environment.md from Stage 1 unchanged.\n'
fi

printf '\n%s failure(s), %s warning(s)\n' "$fails" "$warns"
[ "$fails" -eq 0 ] || exit 1
exit 0
