---
name: exapp-development
description: >-
  Builds a Nextcloud External App (ExApp) in any programming language against the raw AppAPI contract:
  heartbeat, init and enabled endpoints, authentication headers in both directions, the info.xml manifest,
  Docker packaging with an FRP tunnel for HaRP, and the two develop-and-redeploy loops. Use when creating a
  new ExApp, porting an existing service to Nextcloud, or debugging why an ExApp fails to deploy,
  authenticate, or serve its routes.
license: AGPL-3.0-or-later
compatibility: >-
  Needs a Nextcloud instance with AppAPI and a deploy daemon (the nextcloud-dev-setup skill builds one).
  Last verified with Nextcloud master (35), AppAPI 35.0.0-dev.1, HaRP 0.4.3.
---

# ExApp development (any language)

An ExApp is a separate HTTP service, usually a container, that Nextcloud manages through AppAPI. Nothing in
the contract is Python-specific: implement three small lifecycle endpoints, validate three auth headers, and
package the image with an FRP tunnel, and any language works. This skill teaches that contract, ships a
runnable reference implementation, and gives you two iteration loops (a fast process-restart loop and a
production-like Docker loop).

## How to work

1. Read [references/exapp-development.md](references/exapp-development.md) in full: the contract, both loops,
   the redeploy table, and the capability map.
2. Read the reference app [assets/minimal_exapp/](assets/minimal_exapp/): the entire contract in one
   framework-free Python file plus the smallest correct Dockerfile. To develop in Go, Rust, Node or anything
   else, port `main.py`; for Python, use [nc_py_api](https://github.com/cloud-py-api/nc_py_api) instead, which
   implements all of it.
3. Manifest questions (`info.xml`, routes, `--json-info`, env allow-list, mounts, Kubernetes roles):
   [references/exapp-contract.md](references/exapp-contract.md).

## Facts that save hours

- Under a HaRP daemon (`HP_SHARED_KEY` in the env) listen on the unix socket `/tmp/exapp.sock`; everywhere
  else on TCP `APP_HOST:APP_PORT`.
- No init work? Do not implement `/init` at all: AppAPI treats 404/501 as "no init needed". Otherwise return
  200 immediately and report progress 0..100 in the background; 100 enables the app.
- Never validate the `AA-VERSION` header strictly; the HaRP path rewrites it.
- Rebuilding an image does nothing by itself. Redeploy = bump `<version>` AND `<image-tag>` (keep them equal),
  then `app_api:app:update --info-xml`; same-version updates are a hard no-op.
- A local-only image needs the daemon registry mapping `--registry-from <registry> --registry-to local`, or
  the deploy aborts at pull. Use a fictional registry (the example uses `example.local`).
- "Heartbeat check failed" after minutes with the container running almost always means the image lacks the
  frpc/start.sh tunnel or the app listens on TCP instead of the socket.

## Files

- [references/exapp-development.md](references/exapp-development.md): contract, loops, redeploy semantics,
  capability map, troubleshooting.
- [references/exapp-contract.md](references/exapp-contract.md): the `<external-app>` manifest reference.
- [references/known-exapps.md](references/known-exapps.md): real ExApps, examples (including Go) and wrapper
  libraries to read.
- [assets/minimal_exapp/](assets/minimal_exapp/): runnable reference ExApp (main.py, Dockerfile, start.sh,
  appinfo/info.xml, Makefile with both loops).
- Environment to run all this in: [nextcloud-dev-setup](../nextcloud-dev-setup/SKILL.md). Changing an app that
  is already installed somewhere: [exapp-maintenance](../exapp-maintenance/SKILL.md).
