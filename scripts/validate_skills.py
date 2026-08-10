#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Validate the skills in this repository.

Checks, per skills/<name>/SKILL.md:
  - YAML frontmatter parses and starts at line 1
  - name: present, equals the directory name, lowercase kebab-case, max 64 chars
  - description: present, non-empty, max 1024 chars
  - license: present
  - non-empty body after the frontmatter

Per skills/<name>/references/*.md:
  - carries a "Last verified against:" line (the repo's verified-content promise)

Repo-wide, for every markdown file:
  - every relative link target exists
  - every intra-repo #anchor resolves to a real heading (GitHub-style slugs)

Exit code 0 when clean, 1 when any check fails.
"""

import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*$")

errors: list[str] = []
_anchor_cache: dict[Path, set[str]] = {}


def fail(msg: str) -> None:
    errors.append(msg)


def parse_frontmatter(path: Path) -> tuple[dict, str]:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        fail(f"{path.relative_to(ROOT)}: no YAML frontmatter at line 1")
        return {}, text
    end = text.find("\n---\n", 4)
    if end == -1:
        fail(f"{path.relative_to(ROOT)}: unterminated frontmatter")
        return {}, ""
    try:
        meta = yaml.safe_load(text[4:end]) or {}
    except yaml.YAMLError as exc:
        fail(f"{path.relative_to(ROOT)}: frontmatter is not valid YAML: {exc}")
        return {}, ""
    if not isinstance(meta, dict):
        fail(f"{path.relative_to(ROOT)}: frontmatter is not a mapping")
        return {}, ""
    return meta, text[end + 5:]


def check_skill(skill_dir: Path) -> None:
    skill_md = skill_dir / "SKILL.md"
    rel = skill_md.relative_to(ROOT)
    if not skill_md.is_file():
        fail(f"{skill_dir.relative_to(ROOT)}: missing SKILL.md")
        return
    meta, body = parse_frontmatter(skill_md)

    name = meta.get("name")
    if not isinstance(name, str) or not name:
        fail(f"{rel}: frontmatter needs a non-empty 'name'")
    else:
        if name != skill_dir.name:
            fail(f"{rel}: name '{name}' does not equal directory name '{skill_dir.name}'")
        if not NAME_RE.match(name):
            fail(f"{rel}: name '{name}' is not lowercase kebab-case")
        if len(name) > 64:
            fail(f"{rel}: name longer than 64 characters")

    description = meta.get("description")
    if not isinstance(description, str) or not description.strip():
        fail(f"{rel}: frontmatter needs a non-empty 'description'")
    elif len(description) > 1024:
        fail(f"{rel}: description longer than 1024 characters ({len(description)})")

    if not meta.get("license"):
        fail(f"{rel}: frontmatter needs 'license'")

    if not body.strip():
        fail(f"{rel}: empty body after frontmatter")

    for ref in sorted((skill_dir / "references").glob("*.md")):
        if "Last verified against:" not in ref.read_text(encoding="utf-8"):
            fail(f"{ref.relative_to(ROOT)}: missing 'Last verified against:' line")


def collect_anchors(path: Path) -> set[str]:
    if path in _anchor_cache:
        return _anchor_cache[path]
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    in_fence = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = HEADING_RE.match(line)
        if not m:
            continue
        text = m.group(2).replace("`", "")
        base = re.sub(r"[^\w\- ]", "", text.lower()).replace(" ", "-")
        n = counts.get(base, 0)
        counts[base] = n + 1
        anchors.add(base if n == 0 else f"{base}-{n}")
    _anchor_cache[path] = anchors
    return anchors


def check_links(md_file: Path) -> None:
    text = md_file.read_text(encoding="utf-8")
    for match in LINK_RE.finditer(text):
        raw = match.group(1)
        if raw.startswith(("http://", "https://", "mailto:")):
            continue
        target, _, fragment = raw.partition("#")
        resolved = (md_file.parent / target).resolve() if target else md_file
        if not resolved.exists():
            fail(f"{md_file.relative_to(ROOT)}: broken link '{raw}'")
            continue
        if fragment and resolved.is_file() and resolved.suffix == ".md":
            if fragment not in collect_anchors(resolved):
                fail(f"{md_file.relative_to(ROOT)}: broken anchor '{raw}'")


def main() -> int:
    skills_dir = ROOT / "skills"
    skill_dirs = sorted(d for d in skills_dir.iterdir() if d.is_dir())
    if not skill_dirs:
        fail("no skills found under skills/")
    for skill_dir in skill_dirs:
        check_skill(skill_dir)

    for md_file in sorted(ROOT.rglob("*.md")):
        if "LICENSES" in md_file.parts or ".git" in md_file.parts:
            continue
        check_links(md_file)

    if errors:
        print(f"FAIL: {len(errors)} problem(s)")
        for err in errors:
            print(f"  - {err}")
        return 1
    print(f"OK: {len(skill_dirs)} skills validated; all links and anchors resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())
