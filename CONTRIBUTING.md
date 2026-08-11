<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Contributing

Contributions are welcome: new skills, corrections to existing runbooks, and re-verification against newer
Nextcloud/AppAPI/HaRP releases all help.

## What a skill is here

A skill is a directory under `skills/` following the [Agent Skills](https://agentskills.io) format:

```
skills/<name>/SKILL.md        entry point (frontmatter + short orientation)
skills/<name>/references/     the full runbooks; SKILL.md links them
skills/<name>/assets/         runnable material (code, templates), if any
```

- `SKILL.md` stays short: when to use, how to work, the handful of facts that prevent wasted hours, and a file
  map. The depth lives in `references/`; agents read those when executing (progressive disclosure).
- Frontmatter uses only the vendor-neutral Agent Skills fields, so the skills keep working outside Claude:
  `name` (must equal the directory name, lowercase kebab-case), `description` (third person, says what it does
  AND when to use it; keep it under 1024 characters), `license`, and optionally `compatibility`.

## Authoring rules for runbooks

- **Verified, not plausible**: only write down what was executed against a real environment. Every runbook
  carries a `Last verified against:` line (Nextcloud, AppAPI, HaRP versions and the date); update it when you
  re-verify. Reviewing a runbook does not count as verifying it: three review passes over these pages missed
  claims that a single afternoon of execution disproved.
- **Turn load-bearing claims into checks**: when a sentence would cost someone hours if it were wrong, add a
  check for it to [`tests/verify.py`](tests/README.md) so it can be re-proven instead of re-read.
- **Report what you find upstream**: executing a runbook regularly uncovers real bugs. Fix the runbook here,
  then open an issue on the affected project with the reproduction you already have.
- **Executable by an agent**: imperative voice, stages in order, and a Verify block (command + expected
  output) after every stage. Troubleshooting is symptom-first tables.
- **Portable**: no real secrets ever (placeholders in angle brackets), no values that only exist in one
  person's setup, and "how to verify" preferred over bare assertions.
- **Safe**: destructive commands are marked as requiring explicit human approval.
- **Update in the same change**: when AppAPI/HaRP behavior changes, update the affected runbook in the same
  PR, and note the Nextcloud version if the behavior is version-specific. These runbooks are the canonical
  copy; [nextcloud/app_api](https://github.com/nextcloud/app_api) links here instead of duplicating them.

## Validation

```bash
python3 scripts/validate_skills.py    # frontmatter + internal links (CI runs this)
pip install reuse && reuse lint       # licensing headers (CI runs this)
python3 tests/verify.py --all         # the claims themselves, against a live instance (CI cannot)
```

The first two check structure, the third checks reality; see [tests/README.md](tests/README.md) for the
environment variables that point it at your instance.

## Commits and licensing

- **DCO sign-off is required**: `git commit -s`; the sign-off name/email must match the commit author.
- Commit messages: concise, one line. Reference issues in the PR description, not the commit subject.
- License: [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), [REUSE](https://reuse.software/)-compliant.
  New files need an SPDX header, except files whose format cannot start with a comment (SKILL.md frontmatter,
  JSON); those are covered by `REUSE.toml` annotations.
