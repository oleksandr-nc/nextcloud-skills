<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Acceptance harness

`verify.py` replays the load-bearing claims of each skill against a **live** Nextcloud and reports pass, fail
or skip. It exists because the runbooks promise verified behaviour: reviewing them proves nothing, executing
them does.

Run it before refreshing a runbook's `Last verified against:` line, after any change that touches behaviour,
and whenever a new Nextcloud, AppAPI or HaRP version appears.

It is deliberately not part of CI: the checks need a running Nextcloud with AppAPI, a deploy daemon and a
HaRP container, which the linting workflow does not have. CI validates structure; this validates reality.

## Running it

```bash
python3 tests/verify.py --list                       # what exists
python3 tests/verify.py --skill harp-operations      # one skill
python3 tests/verify.py --all                        # every skill, fast checks only
python3 tests/verify.py --all --include-slow         # also deploys the reference ExApp
```

Point it at your instance with environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `NC_CONTAINER` | `master-nextcloud-1` | Nextcloud container name |
| `OCC` | `docker exec -u www-data $NC_CONTAINER php occ` | full occ command, overrides the above |
| `NC_URL` | `http://nextcloud.local` | base URL, must serve `/exapps/` |
| `DAEMON` | `local-harp` | a `docker-install` HaRP daemon |
| `HARP_CONTAINER` | `appapi-harp` | HaRP container name |
| `NC_ADMIN`, `NC_ADMIN_PASS` | unset | admin credentials; without them the OCS checks skip |

Example against the environment the [nextcloud-dev-setup](../skills/nextcloud-dev-setup/SKILL.md) skill
builds:

```bash
NC_URL=http://nextcloud.local DAEMON=local-harp HARP_CONTAINER=master-appapi-harp-1 \
NC_ADMIN=admin NC_ADMIN_PASS=admin \
python3 tests/verify.py --all --include-slow
```

`HARP_CONTAINER` is not optional here. The default, `appapi-harp`, is the name the production
Quickstart gives the container with `docker run --name`; the dev environment deliberately sets no
`container_name`, so compose names it `master-appapi-harp-1`. Without the override every
harp-operations check fails with `no such container: appapi-harp`.

## What it guarantees

- Checks only create their own throwaway objects and clean up in a `finally` block.
- The slow check refuses to run when an app named `minimal_exapp` is already registered, so it can never
  disturb a real installation.
- Nothing else is modified: no daemon is unregistered, no existing app is touched, no data volume other than
  the reference app's own is removed.

A `SKIP` is not a pass. It means the precondition was absent (no credentials, no HaRP container, an app in
the way); fix the precondition if you need the guarantee.

## Adding checks

Write a function with a one-line docstring stating the claim it proves, return a short detail string on
success, raise `AssertionError` on failure and `Skip` when the precondition is missing. Then list it under
the right skill in `CHECKS`, and add its name to `SLOW` if it builds images or deploys containers.

Each check should map to a sentence a runbook actually promises. If a claim is worth writing down, it is
worth being able to re-prove.
