<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Security

This repository contains documentation and example code only; it runs no service of its own.

- A mistake in these documents with security impact (an instruction that would expose a port, weaken
  authentication, or leak a secret): open a GitHub issue, or use GitHub's private vulnerability reporting on
  this repository if the details should not be public.
- Vulnerabilities in Nextcloud itself, AppAPI, HaRP, nc_py_api or any ExApp: report them through the
  Nextcloud security process at https://hackerone.com/nextcloud (see https://nextcloud.com/security/), not
  here.

The runbooks deliberately flag their own risk surface: mounting the Docker socket is root-equivalent, shared
keys must never be committed, and destructive commands require explicit human approval. If you find a place
where they fail to do that, treat it as the first bullet above.
