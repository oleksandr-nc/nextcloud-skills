---
name: exapp-maintenance
description: >-
  Fixes or extends an ExApp that is already installed on a Nextcloud instance, development or production:
  identify the installed version, clone the matching sources, diagnose from container logs, patch, rebuild
  the Docker image under its original name, and redeploy in place with occ app_api:app:update while
  preserving the app's secret, configuration and data volume. Use when a user reports that an installed
  ExApp is broken or asks for a capability it lacks, for example adding a model to a local AI app.
license: AGPL-3.0-or-later
compatibility: >-
  Works against any docker-install HaRP daemon you control (not Kubernetes daemons; manual-install apps are
  just edited and restarted). Last verified with Nextcloud master (35), AppAPI 35.0.0-dev.1, HaRP 0.4.3.
---

# Fix or extend an installed ExApp

ExApps are open source and run from Docker images, so any installed ExApp can be changed locally without
waiting for a release: get the source at the installed version, change it, rebuild the image, and make the
instance run the rebuilt one. The user's part is one sentence ("add EuroLLM support to llm2", "llm2 never
reports progress, fix it"); this skill is the loop the agent executes on their behalf.

## How to work

Read [references/exapp-ai-maintenance.md](references/exapp-ai-maintenance.md) in full and execute its
numbered runbook: identify what is running, clone the source at the INSTALLED tag, diagnose, patch, bump the
version, rebuild under the original image name, registry-map the daemon to local images, update with
`--info-xml`, verify. It ends with a worked example (adding the EuroLLM model to llm2, verified end to end)
and a symptom-first troubleshooting table.

## Ground rules

- Never use `--rm-data`; the app's data volume and configuration belong to the user.
- Fix what is running: check out the tag matching the installed version, not the moving main branch.
- Bump `<version>` with a FOURTH segment (`2.8.0` becomes `2.8.0.1`): it sorts above the installed release but
  below upstream's next patch, so a future store update takes over cleanly. An unbumped rebuild never deploys;
  same-version `app:update` is a verified no-op.
- Keep `<image-tag>` equal to `<version>`; AppAPI deploys `<image-tag>` while `app:update` compares
  `<version>`.
- Registry mappings are daemon-wide. On a shared daemon, remove the mapping right after the update.
- Finish with verification the user can see (the feature works, `app:list` shows the new version), and offer
  to upstream the change; local rebuilds are for immediacy, upstream is the fix.

## Files

- [references/exapp-ai-maintenance.md](references/exapp-ai-maintenance.md): the eight-step runbook, the
  EuroLLM worked example, return-to-stock instructions, troubleshooting.
- Redeploy semantics in a development setting: [exapp-development](../exapp-development/SKILL.md). Lifecycle
  command reference: [exapp-operations](../exapp-operations/SKILL.md).
