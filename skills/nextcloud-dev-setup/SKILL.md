---
name: nextcloud-dev-setup
description: >-
  Sets up a complete local Nextcloud development environment with Docker Compose using nextcloud-docker-dev:
  Nextcloud from source, the AppAPI app, a HaRP deploy daemon, /exapps/ browser routing, and a smoke-tested
  ExApp deploy as the acceptance gate. Use when asked to create or bootstrap a Nextcloud dev instance, prepare
  an environment for ExApp development, or repair a broken nextcloud-docker-dev setup.
license: AGPL-3.0-or-later
compatibility: >-
  Linux with Docker Engine, docker compose v2, git, curl, make and sudo; 4+ vCPUs, 8+ GB RAM, 40+ GB disk
  recommended. macOS is covered by references/macos.md (host steps not yet verified on a Mac). Last verified
  with Nextcloud master (35), AppAPI 35.0.0-dev.1, HaRP 0.4.3.
---

# Nextcloud development environment setup

Builds a disposable local Nextcloud development environment on
[nextcloud-docker-dev](https://github.com/nextcloud/nextcloud-docker-dev), then layers everything ExApp
development needs on top: AppAPI enabled, a HaRP deploy daemon (production-like docker-install) plus a
manual-install daemon (fast loop), `/exapps/` routed through the bundled nginx proxy, and a real reference
ExApp deployed as proof the whole chain works.

## How to execute

Read [references/dev-environment.md](references/dev-environment.md) in full, then execute its stages 1 to 7 in
order. Every stage ends with a Verify block; do not continue past a failed Verify (each has a matching "If it
fails" entry). Stage 7, deploying the bundled
[minimal_exapp](../exapp-development/assets/minimal_exapp/) through HaRP, is the acceptance gate: when its
endpoints answer over `http://nextcloud.local/exapps/...`, the environment is done.

## Rules that prevent the common disasters

- Never run `docker compose down -v` and never delete `workspace/` or named volumes without explicit human
  approval; they hold every instance's data.
- Never edit tracked files of the nextcloud-docker-dev checkout. The whole AppAPI overlay lives in untracked
  files (`.env`, `docker-compose.override.yml`, `data/nginx/vhost.d/`).
- The HaRP shared key must be byte-identical between the compose override (`HP_SHARED_KEY`) and the
  `daemon:register --harp_shared_key` value; a mismatch is the number one install failure.
- After creating a new `data/nginx/vhost.d/<host>` file, `docker compose restart proxy`; a plain nginx reload
  never picks up a file that did not exist when the config was generated.
- Kill development processes by exact PID only, and use dev-only secrets you never reuse elsewhere.

## Files

- [references/dev-environment.md](references/dev-environment.md): the full staged runbook (bring-up, daemons,
  smoke test, daily operation, reset and recovery, symptom-first troubleshooting).
- [references/macos.md](references/macos.md): read first on a Mac. Which setup to choose, the Docker socket
  path, why `DOMAIN_SUFFIX` should not stay `.local`, and which ExApp images have arm64 builds.
- [assets/macos-preflight.sh](assets/macos-preflight.sh): checks a Mac and prints the `.env` lines to use.
- Next steps: build your own ExApp with the [exapp-development](../exapp-development/SKILL.md) skill; operate
  a real instance with [exapp-operations](../exapp-operations/SKILL.md).
