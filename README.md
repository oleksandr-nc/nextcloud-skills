<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Nextcloud Skills

Skills for AI agents working with **Nextcloud**: setting up development environments, building Nextcloud apps
in PHP and External Apps (ExApps) in any language, and operating or fixing them on real instances, development
and production alike.

Three terms carry the whole repository: **AppAPI** is the Nextcloud component that runs ExApps (services
living in their own containers next to Nextcloud), **HaRP** is AppAPI's recommended reverse-proxy deploy
daemon, and **occ** is Nextcloud's admin console. The skills teach everything else.

The skills use the open [Agent Skills](https://agentskills.io) format (a `SKILL.md` file with plain-markdown
instructions plus bundled references and assets), so they work with **Claude Code and claude.ai, ChatGPT and
Codex, Gemini CLI, VS Code**, and any other agent or human that can read files. Only the vendor-neutral
frontmatter fields are used.

## The skills

| Skill | Use it to |
|---|---|
| [nextcloud-dev-setup](skills/nextcloud-dev-setup/SKILL.md) | Build a local Nextcloud development environment on [nextcloud-docker-dev](https://github.com/nextcloud/nextcloud-docker-dev): Nextcloud from source, AppAPI, a HaRP deploy daemon, and a smoke-tested ExApp deploy |
| [exapp-development](skills/exapp-development/SKILL.md) | Write an ExApp in **any language** against the raw AppAPI contract, with a runnable framework-free reference app and two iteration loops |
| [exapp-maintenance](skills/exapp-maintenance/SKILL.md) | Fix or extend an ExApp that is already installed: clone matching sources, patch, rebuild the image, redeploy in place without losing data |
| [exapp-operations](skills/exapp-operations/SKILL.md) | Install and operate AppAPI and ExApps with occ on Docker, Kubernetes, remote hosts or AIO, and troubleshoot symptom-first |
| [harp-operations](skills/harp-operations/SKILL.md) | Run and debug HaRP itself: probes, configuration, log decoding, certificates, upgrades and load-related failures |
| [nextcloud-ai-stack](skills/nextcloud-ai-stack/SKILL.md) | Install, verify and debug Nextcloud's AI features: Assistant, Task Processing and the provider apps behind them, local or external |
| [nextcloud-php-app](skills/nextcloud-php-app/SKILL.md) | Build a Nextcloud **PHP app** from an empty directory to a release tarball: routes, templates, database, settings, a Vue frontend, PHPUnit and Psalm, packaging, and Playwright tests against a real instance |

Every runbook was executed end to end against a live environment before being written down, and carries a
"Last verified against" line naming the Nextcloud, AppAPI and HaRP versions it was checked with. The
load-bearing claims are also executable: [`tests/verify.py`](tests/README.md) replays them against a live
instance, so a skill can be re-proven rather than re-read. The content is maintained alongside AppAPI and
updated as AppAPI evolves.

## Using the skills

### Claude Code (plugin)

```
/plugin marketplace add oleksandr-nc/nextcloud-skills
/plugin install nextcloud-skills@nextcloud-skills
```

The skills then load automatically whenever a matching task comes up, and can be invoked directly by name.

### Claude Code (manual, no plugin system)

Clone the repository and copy or symlink the skills you want into your skills directory:

```bash
git clone https://github.com/oleksandr-nc/nextcloud-skills
ln -s "$(pwd)/nextcloud-skills/skills/"* ~/.claude/skills/
```

(Use a project's `.claude/skills/` instead of `~/.claude/skills/` to scope them to one project.)

### Any other agent (ChatGPT, Codex, Gemini CLI, DeepSeek, ...)

Clone the repository (or fetch single files raw from GitHub) and point your agent at
[AGENTS.md](AGENTS.md), which routes to the right skill, or directly at the relevant
`skills/<name>/SKILL.md`. The files are self-contained markdown; no runtime or tooling is required to follow
them. Tools that support the Agent Skills format natively can install the `skills/<name>` directories in
their usual way.

### Recommended: give your agent a browser

Several skills verify user interfaces. An agent without a browser can only fetch HTML, which cannot show
whether a script ran, whether the Content Security Policy blocked it, or what a component actually rendered.
An MCP browser server (`chrome-devtools-mcp`, or `@playwright/mcp`) fixes that, and its accessibility
snapshots hand you the roles and accessible names that test locators need. Setup, verified:
[dev-environment.md, Stage 8](skills/nextcloud-dev-setup/references/dev-environment.md#stage-8-optional-give-the-agent-a-browser).

## Repository anatomy

```
skills/<name>/SKILL.md        the entry point: when to use, how to work, the critical facts
skills/<name>/references/     the full runbooks the skill executes from
skills/<name>/assets/         runnable material (reference app, diagnostic scripts)
tests/verify.py               replays each skill's load-bearing claims against a live instance
scripts/validate_skills.py    structure, links, anchors and the verified-against promise
```

`SKILL.md` is deliberately short; agents read the referenced runbooks when they actually execute the task
(progressive disclosure). The runbooks are written stage by stage with Verify blocks and symptom-first
troubleshooting tables, so an agent can execute them unaided and a human can follow along.

## Roadmap

Planned additions, in no particular order: an nc_py_api (Python ExApp) quickstart, Task Processing (AI
provider) development, Talk bots, ExApp UI integration, and backup, restore and daemon migration.
Suggestions and contributions are welcome through issues and pull requests.

## Status and support

This repository is the **canonical home** of the AppAPI guides: the
[nextcloud/app_api](https://github.com/nextcloud/app_api) repository's `AGENTS.md` points here.

Maintained by the Nextcloud AppAPI maintainers; the repository is planned to move under the Nextcloud GitHub
organization (GitHub redirects will keep existing links working). Questions and documentation problems:
GitHub issues, answered on a best-effort basis. Security reports: see [SECURITY.md](SECURITY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the skill format, authoring rules and validation. Every commit
needs a DCO sign-off (`git commit -s`).

## License

[AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt). This repository is
[REUSE](https://reuse.software/)-compliant.
