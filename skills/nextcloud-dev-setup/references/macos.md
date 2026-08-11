<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# ExApp development on macOS

A detailed runbook, part of the [nextcloud-dev-setup](../SKILL.md) skill. Read this before
[dev-environment.md](dev-environment.md) if you work on a Mac; the stages there then apply unchanged.

> **Verification status.** The platform facts in this page (image architectures, upstream behaviour, the
> configuration knobs) were verified from the registries and sources on a Linux host. The **host-side macOS
> steps have not yet been executed on a Mac**, so unlike the rest of this repository they are reasoned rather
> than proven. Run [macos-preflight.sh](../assets/macos-preflight.sh) to have your own machine answer the
> questions this page can only describe.

Last verified against: image architectures on ghcr.io, nextcloud-docker-dev df4ca69 sources, AppAPI
35.0.0-dev.1, HaRP 0.4.3, checked from Linux on 2026-08-11. macOS host steps: not yet verified.

## What actually differs on a Mac

Four differences, and everything else follows from them.

1. **There is no Linux kernel.** Docker runs inside a virtual machine, so the daemon socket lives wherever
   your engine puts it, bind mounts cross a VM boundary, and `net=host` does not behave the way it does on
   Linux.
2. **Apple Silicon is arm64.** Images without an arm64 build need emulation, which is fine for a web service
   and useless for local model inference.
3. **`.local` belongs to mDNS.** It is reserved for multicast DNS (RFC 6762), and it is the default
   `DOMAIN_SUFFIX` of nextcloud-docker-dev.
4. **Host tooling is BSD, not GNU.** `getent` does not exist, and flags differ.

## Choose the setup that matches the work

There is no single right answer; pick per task.

| Work | Setup | Why |
|---|---|---|
| Day-to-day ExApp coding (the fast loop) | Native engine on macOS, [manual-install loop](../../exapp-development/references/exapp-development.md) | Your app runs natively with your debugger and IDE while Nextcloud runs in containers. Every image this needs has an arm64 build |
| Production-like deploys: images, frpc, routes, the full contract | A Linux VM (Lima, UTM, Parallels, Multipass) or a remote Linux host | This is exactly the environment the rest of this repository is verified against, and snapshots make mistakes cheap |
| AI ExApps (llm2, context_chat_backend) | A remote **amd64** Linux host, ExApps deployed there | Not a preference: those images have no arm64 build, and emulated inference is not usable. See [remote-daemon.md](../../exapp-operations/references/remote-daemon.md) |

A Linux VM fixes the host-OS differences, not the architecture one: an arm64 VM on Apple Silicon still cannot
run an amd64-only image without emulation.

## Apple Silicon: what has an arm64 build

Verified from ghcr.io on 2026-08-11:

| Image | arm64 |
|---|---|
| `nextcloud-appapi-harp` (the deploy daemon) | yes |
| `nextcloud-dev-php85`, `nextcloud-dev-nginx` (the dev environment) | yes |
| `test-deploy` (the admin UI's Test deploy button) | yes |
| `app-skeleton-python` | yes |
| `translate2`, `stt_whisper2`, `summary_bot` | yes |
| `llm2` | **no, amd64 only** |
| `context_chat_backend` | **no** |

So the whole core path (environment, HaRP, first deploy, the reference ExApp) is native on Apple Silicon.
Only the heavy AI apps are not. For those, either enable your engine's amd64 emulation and accept the
performance, or put them on a remote amd64 host.

Your own images: build multi-arch (`docker buildx build --platform linux/amd64,linux/arm64`) if colleagues or
production run on the other architecture. An arm64-only image will not deploy on an amd64 server.

## What your engine must provide

Rather than ranking products, these are the requirements. Docker Desktop, OrbStack, Colima and Rancher
Desktop can each satisfy them; the preflight script checks yours.

- **A Docker-compatible socket a container can bind-mount.** HaRP manages containers through it. On macOS it
  is often not at `/var/run/docker.sock`, so set `DOCKER_SOCKET` in `.env` to the real path
  (nextcloud-docker-dev already reads it, and the HaRP override in
  [dev-environment.md](dev-environment.md) does too).
- **`host.docker.internal` resolvable from inside a container**, which the `manual_dev` daemon uses to reach
  the ExApp process running on your Mac.
- **The ability to publish ports 80 and 443** for the proxy.
- **Enough VM memory**: 8 GB or more, and more again if you run AI ExApps.

## Adjustments to the standard runbook

- **`DOMAIN_SUFFIX`**: change it from `.local` to `.test` in `.env` before the first start. `.test` is
  reserved for exactly this purpose (RFC 6761) and avoids mDNS entirely; `.local` sends every hostname
  through Bonjour. The proxy snippet file in Stage 5 follows the suffix, so it becomes
  `data/nginx/vhost.d/nextcloud.test`, and the URLs used everywhere become `http://nextcloud.test`.
- **`DOCKER_SOCKET`**: set it in `.env` if your engine does not expose `/var/run/docker.sock`.
- **Always pass `--net` when registering a daemon.** Its default is `host`, which does not work as expected
  on macOS. The Stage 6 command already passes `--net master_default`; keep it.
- **Do not use `--harp_exapp_direct`** on macOS. It requires HaRP to reach the ExApp container directly and
  disallows host networking, which is exactly the fragile part here.
- Expect bind-mounted source trees (`workspace/server`) to be slower than on Linux; enable your engine's
  fastest file-sharing implementation (VirtioFS on Docker Desktop).

## Preflight

```bash
sh skills/nextcloud-dev-setup/assets/macos-preflight.sh
```

It reports the engine and the socket path to configure, the CPU architecture and whether amd64 emulation
works, whether `host.docker.internal` resolves from a container, whether ports 80 and 443 are free, and the
memory available to the VM. It ends with the exact `.env` lines for your machine. It changes nothing; it does
run two throwaway containers from a small image.

## Troubleshooting (symptom first)

| Symptom | Cause and fix |
|---|---|
| HaRP starts, then cannot manage containers | The socket mount is wrong. Set `DOCKER_SOCKET` to your engine's real path and recreate HaRP |
| Daemon registration fails or ExApps are unreachable | The daemon was registered without `--net`, so it defaulted to `host`. Unregister and register again with the compose network |
| Manual-install app never receives requests | `host.docker.internal` does not resolve in your engine, or the app listens on `127.0.0.1` instead of `0.0.0.0` |
| Hostnames resolve slowly or intermittently | `.local` is going through mDNS. Switch `DOMAIN_SUFFIX` to `.test` and re-run `./scripts/update-hosts` |
| `getent: command not found` | A Linux-only command; use `python3 -c "import socket; print(socket.gethostbyname('nextcloud.test'))"` |
| An ExApp deploy pulls forever or crashes immediately | The image has no arm64 build. Check with `docker manifest inspect <image>`, then use emulation or a remote amd64 host |
| Inference is unusably slow | An amd64 model image under emulation. Move it to a remote amd64 host |

## Related

- [dev-environment.md](dev-environment.md): the stages themselves, unchanged on macOS.
- [exapp-development.md](../../exapp-development/references/exapp-development.md): the two development loops.
- [remote-daemon.md](../../exapp-operations/references/remote-daemon.md): running ExApps on another host,
  which is the answer for AI apps and GPUs.
