<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# ExApp development on macOS

A detailed runbook, part of the [nextcloud-dev-setup](../SKILL.md) skill. Read this before
[dev-environment.md](dev-environment.md) if you work on a Mac.

**The headline: on Apple Silicon with a mainstream engine, the standard runbook runs unmodified.** Stages 1
to 7 of [dev-environment.md](dev-environment.md) were executed on a Mac with nothing changed, including the
default `DOMAIN_SUFFIX=.local`, and the acceptance gate passed. This page exists for the two cases where a Mac
genuinely differs (amd64-only images, and engines that hide the Docker socket) and to stop you from applying
"fixes" you do not need.

Last verified against: macOS 26.5 (25F71), Apple M5 Pro, Docker Desktop 4.86.0 with Docker Engine 29.7.2 and
compose v5.3.1; Nextcloud master (35.0.0 beta 2), AppAPI 35.0.0-dev.1, HaRP 0.4.4, nextcloud-docker-dev
df4ca69, on 2026-08-17.

## What actually differs on a Mac

Three differences, and everything else follows from them.

1. **There is no Linux kernel.** Docker runs inside a virtual machine, so the daemon socket lives wherever
   your engine puts it, bind mounts cross a VM boundary, and `net=host` does not behave the way it does on
   Linux.
2. **Apple Silicon is arm64.** Images without an arm64 build need emulation, which is fine for a web service
   and useless for local model inference.
3. **Host tooling is BSD, not GNU.** `getent` does not exist, and flags differ. A full audit of this
   repository found `getent` to be the only offender; it is gone.

`.local` is a fourth candidate that turns out not to matter in practice - see
[The `.local` question](#the-local-question).

## Choose the setup that matches the work

There is no single right answer; pick per task.

| Work | Setup | Why |
|---|---|---|
| Day-to-day ExApp coding (the fast loop) | Native engine on macOS, [manual-install loop](../../exapp-development/references/exapp-development.md) | Your app runs natively with your debugger and IDE while Nextcloud runs in containers. Every image this needs has an arm64 build |
| Production-like deploys: images, frpc, routes, the full contract | Native engine on macOS works (verified end to end); a Linux VM or remote host if you want to match a production box exactly | The `docker-install` loop through HaRP was verified on macOS. A VM only buys you snapshots and an exact match to the Linux CI environment |
| AI ExApps (llm2, context_chat_backend) | A remote **amd64** Linux host, ExApps deployed there | Not a preference: those images have no arm64 build, and emulated inference is not usable. See [remote-daemon.md](../../exapp-operations/references/remote-daemon.md) |

A Linux VM fixes the host-OS differences, not the architecture one: an arm64 VM on Apple Silicon still cannot
run an amd64-only image without emulation.

## Apple Silicon: what has an arm64 build

Verified from ghcr.io on 2026-08-17 (`docker manifest inspect`):

| Image | arm64 |
|---|---|
| `nextcloud/nextcloud-appapi-harp:release` (the deploy daemon) | yes |
| `nextcloud/nextcloud-dev-php85`, `nextcloud-dev-nginx`, `nextcloud-dev-mailhog` | yes |
| `mariadb:10.6`, `redis:8` (the rest of the compose stack) | yes |
| `nextcloud/test-deploy:release` (the admin UI's Test deploy button) | yes |
| `nextcloud/translate2`, `stt_whisper2`, `summary_bot` | yes |
| `nextcloud/llm2` | **no, amd64 only** |
| `nextcloud/context_chat_backend` | **no, single amd64 manifest** |

So the whole core path (environment, HaRP, first deploy, the reference ExApp) is native on Apple Silicon;
`docker inspect` on the running containers confirms `linux/arm64` throughout. Only the heavy AI apps are not.
For those, either enable your engine's amd64 emulation and accept the performance, or put them on a remote
amd64 host.

The reference ExApp builds arm64-native in about 8 seconds (`alpine:3.21` has an `frp` package for aarch64,
which `start.sh` needs) and deploys through HaRP in about 11 seconds.

Your own images: build multi-arch (`docker buildx build --platform linux/amd64,linux/arm64`) if colleagues or
production run on the other architecture. An arm64-only image will not deploy on an amd64 server.

## What your engine must provide

Rather than ranking products, these are the requirements. Docker Desktop, OrbStack, Colima and Rancher
Desktop can each satisfy them; the preflight script checks yours.

- **A Docker-compatible socket a container can bind-mount.** HaRP manages containers through it. Verified on
  Docker Desktop: with "Allow the default Docker socket to be used" enabled, `/var/run/docker.sock` is a
  symlink to `~/.docker/run/docker.sock` and the compose default works untouched. Only set `DOCKER_SOCKET`
  when `/var/run/docker.sock` is genuinely absent - see [The Docker socket](#the-docker-socket).
- **`host.docker.internal` resolvable from inside a container**, which the `manual_dev` daemon uses to reach
  the ExApp process running on your Mac. Verified working: the ExApp received requests with
  `Host: host.docker.internal:9080`.
- **The ability to publish ports 80 and 443** for the proxy.
- **Enough VM memory**: 8 GB or more, and more again if you run AI ExApps. The full stack (Nextcloud, MariaDB,
  Redis, mail, proxy, HaRP and one ExApp) ran comfortably in a VM reporting 7.7 GiB.
- **A fast file-sharing implementation** for the bind-mounted source tree - see
  [Is the bind mount fast enough](#is-the-bind-mount-fast-enough).

## The Docker socket

The trap here is diagnosing the socket with `docker context inspect`. On Docker Desktop that reports
`unix:///Users/<you>/.docker/run/docker.sock`, which looks like a non-default path that must be configured.
It is not the whole picture: Docker Desktop also creates `/var/run/docker.sock` as a symlink to it when
"Allow the default Docker socket to be used (requires password)" is enabled in Settings > Advanced. When that
symlink exists, `${DOCKER_SOCKET-/var/run/docker.sock}` in both the compose file and the HaRP override
resolves correctly and **`DOCKER_SOCKET` does not belong in your `.env` at all**.

Setting it unnecessarily is not harmful, but it is one more machine-specific line to explain to the next
person. The test that matters is not "does a socket exist at path X" but "can a container bind-mount it and
reach the engine":

```bash
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock alpine:3.21 test -S /var/run/docker.sock \
    && echo "usable, DOCKER_SOCKET not needed"
```

[macos-preflight.sh](../assets/macos-preflight.sh) runs exactly this against every candidate path and tells
you which one to use. Verified end to end: HaRP reported `{"docker": true}` and deployed, updated and removed
ExApp containers through the mounted symlink without any `DOCKER_SOCKET` setting.

## The `.local` question

**`.local` works on macOS.** This was the biggest open question about this page and the answer is that
`/etc/hosts` entries short-circuit mDNS entirely.

macOS does route the `local` domain to mDNS (`scutil --dns` shows `domain: local, options: mdns`), and a
`.local` name that is *not* in `/etc/hosts` costs a full mDNS timeout - measured at 8.4 s to fail, against
2.6 s for a `.test` name. But `bootstrap.sh` runs `scripts/update-hosts`, so every name the runbook uses *is*
in `/etc/hosts`, and then:

| Name | Median resolution |
|---|---|
| `nextcloud.local` (in `/etc/hosts`) | 0.53 ms |
| `nextcloud.test` (in `/etc/hosts`) | 0.27 ms |
| `localhost` | 0.12 ms |

A quarter of a millisecond is not a reason to diverge from the runbook. Stages 1 to 7 and both development
loops were executed on `DOMAIN_SUFFIX=.local` with no resolution problems at all.

**So: leave `DOMAIN_SUFFIX` alone.** `.test` is reserved for this purpose by RFC 6761 and is marginally
tidier, but treat it as taste, not as a fix. If you want it anyway, the cost is real and the ordering is
fiddly, because `bootstrap.sh` writes `.env` and runs `scripts/update-hosts` in the same pass:

```bash
./bootstrap.sh app_api            # writes .env with DOMAIN_SUFFIX=.local, adds the .local names
sed -i '' 's/^DOMAIN_SUFFIX=.local$/DOMAIN_SUFFIX=.test/' .env
./scripts/update-hosts            # adds the .test names (sudo)
# only now: docker compose up -d nextcloud
```

Then every `nextcloud.local` in the runbook becomes `nextcloud.test`, including the Stage 5 snippet file name
(`data/nginx/vhost.d/nextcloud.test`), `NC_INSTANCE_URL` in the HaRP override, both `daemon:register` URLs,
and `NEXTCLOUD_URL` for the manual loop (`make run` defaults to `http://nextcloud.local`, so pass
`NEXTCLOUD_URL=http://nextcloud.test make run`).

Switching **after** the first start costs more, and this was verified the hard way: the instance answers
`{"error": "Trusted domain error.", "code": 15}` until you also run

```bash
./scripts/occ.sh nextcloud -- config:system:set trusted_domains 5 --value=nextcloud.test
./scripts/occ.sh nextcloud -- config:system:set overwrite.cli.url --value=http://nextcloud.test
```

and re-register both daemons, whose stored `nextcloud_url` still points at the old name. It does all work
afterwards - the acceptance gate and the harness pass on `.test` too - but there is nothing to gain.

## Is the bind mount fast enough

Yes, with VirtioFS. Measured on the verified setup, with the Nextcloud source tree bind-mounted from the Mac:

| Operation | Bind mount | Container-native | Verdict |
|---|---|---|---|
| Read all 2334 files in `lib/` | 255 ms | 14 ms | ~18x slower |
| Stat-walk the same tree | 549 ms | 460 ms | ~1.2x slower |
| `GET /status.php` | 18 ms | - | fine |
| `GET /index.php/login` (full bootstrap) | 49 ms | - | fine |
| `occ status` (fresh PHP process, no opcache reuse) | 0.43 s | - | fine |

The raw read penalty is large but PHP's opcache hides almost all of it, and the numbers a developer actually
waits on are unremarkable. Nextcloud installed from scratch in 25 s.

Confirm your engine is on the fast path - inside the VM the share should be `virtiofs`, not `9p` or FUSE:

```bash
docker run --rm --privileged --pid=host alpine:3.21 nsenter -t 1 -m -u -n -i \
    sh -c 'mount | grep -i virtiofs'
```

On Docker Desktop, VirtioFS is under Settings > General > file sharing implementation.

## Adjustments to the standard runbook

Shorter than you would expect. In order of how likely you are to need them:

- **`DOCKER_SOCKET`**: set it in `.env` only if your engine does not expose `/var/run/docker.sock`. Run the
  preflight rather than guessing.
- **Always pass `--net` when registering a daemon.** Its default is `host`, which does not work as expected
  on macOS. The Stage 6 command already passes `--net master_default`; keep it.
- **Do not use `--harp_exapp_direct`** on macOS. It requires HaRP to reach the ExApp container directly and
  disallows host networking, which is exactly the fragile part here. (Not exercised in the verification run;
  the standard FRP tunnel path was, and works.)
- **`DOMAIN_SUFFIX`**: leave it at `.local`. See [The `.local` question](#the-local-question).
- **Killing the manual-loop process**: on macOS the framework Python reports itself as `Python main.py`, not
  `python3 main.py`, so `pgrep -f "python3 main.py"` silently finds nothing. Use
  `ps -Ao pid,command | grep "[m]ain.py"` and kill the exact PID, which is what the runbook asks for anyway.
- **Running the acceptance harness**: pass `HARP_CONTAINER=master-appapi-harp-1`. The default is the name the
  production Quickstart uses; the dev environment deliberately lets compose name the container.

## Preflight

```bash
sh skills/nextcloud-dev-setup/assets/macos-preflight.sh
```

It reports the engine and compose version, the CPU, memory and free disk the VM has, which socket path to use
(after proving a container can actually bind-mount it), whether amd64 emulation works, whether
`host.docker.internal` resolves from a container, and whether ports 80 and 443 are free. It ends with the
`.env` lines for your machine, which on a healthy Docker Desktop is nothing at all. It changes nothing; it
does pull `alpine:3.21` and run throwaway containers from it.

## Troubleshooting (symptom first)

| Symptom | Cause and fix |
|---|---|
| HaRP starts, then cannot manage containers | The socket mount is wrong. Run the preflight; set `DOCKER_SOCKET` to the path it reports and recreate HaRP |
| Daemon registration fails or ExApps are unreachable | The daemon was registered without `--net`, so it defaulted to `host`. Unregister and register again with the compose network |
| Manual-install app never receives requests | `host.docker.internal` does not resolve in your engine, or the app listens on `127.0.0.1` instead of `0.0.0.0` |
| `{"error": "Trusted domain error.", "code": 15}` | You changed `DOMAIN_SUFFIX` after the first start. Add the new host to `trusted_domains` and update `overwrite.cli.url`; see [The `.local` question](#the-local-question) |
| A hostname does not resolve at all, and takes ~8 s to say so | It is a `.local` name missing from `/etc/hosts`, so it went to mDNS and timed out. Re-run `./scripts/update-hosts` |
| `getent: command not found` | A Linux-only command; use `python3 -c "import socket; print(socket.gethostbyname('nextcloud.local'))"` |
| `pgrep -f "python3 main.py"` finds nothing | macOS framework Python renames itself to `Python`. Use `ps -Ao pid,command \| grep "[m]ain.py"` |
| An ExApp deploy pulls forever or crashes immediately | The image has no arm64 build. Check with `docker manifest inspect <image>`, then use emulation or a remote amd64 host |
| Inference is unusably slow | An amd64 model image under emulation. Move it to a remote amd64 host |
| The source tree feels slow | Your engine is sharing it over 9p or FUSE rather than VirtioFS; see [Is the bind mount fast enough](#is-the-bind-mount-fast-enough) |

## Related

- [dev-environment.md](dev-environment.md): the stages themselves, verified unchanged on macOS.
- [exapp-development.md](../../exapp-development/references/exapp-development.md): the two development loops,
  both verified on macOS.
- [remote-daemon.md](../../exapp-operations/references/remote-daemon.md): running ExApps on another host,
  which is the answer for AI apps and GPUs.
