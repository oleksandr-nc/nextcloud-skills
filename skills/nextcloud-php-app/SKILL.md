---
name: nextcloud-php-app
description: >-
  Builds a Nextcloud app in PHP, the kind that runs inside the Nextcloud process: the app manifest and
  bootstrap class, controllers and attribute routes, templates and page scripts, navigation entries, and
  browser-level verification with Playwright against a real instance. Use when creating a new Nextcloud app,
  adding a page, route or navigation entry to one, or setting up automated UI tests for it. For services that
  run in their own container, use exapp-development instead.
license: AGPL-3.0-or-later
compatibility: >-
  Nextcloud 33, 34 or 35 with a development instance and shell access; Playwright needs Node 20+. Last
  verified with Nextcloud master (35), PHP 8.3, Playwright 1.62.
---

# Nextcloud PHP apps

A PHP app runs **inside** Nextcloud: same process, same request, direct access to the server's APIs through
dependency injection. That makes it the right choice for UI, routes, settings, storage and events, and the
wrong choice for anything long-running or written in another language, which belongs in an
[ExApp](../exapp-development/SKILL.md).

This skill goes from an empty directory to an installed app with a page, an API route, a navigation entry and
a passing browser test suite.

## How to work

1. [references/php-app-development.md](references/php-app-development.md): what an app is made of, then the
   scaffold, installed and verified on a real instance.
2. [assets/minimal_php_app/](assets/minimal_php_app/): the runnable reference app. Copy it and rename, rather
   than assembling files from memory.
3. [references/php-app-ui-testing.md](references/php-app-ui-testing.md): Playwright against a real Nextcloud,
   including the locator traps that make correct apps look broken.

## Facts that save hours

- **Routes are deny-by-default.** Without `#[NoAdminRequired]` a route is admin-only, and every route needs a
  logged-in user unless it carries `#[PublicPage]`. An unauthenticated request to a working route answers
  `401`, not `404`: use that to tell "route missing" from "route protected".
- `Util::addScript($appId, 'main')` looks for `js/main.mjs` first and falls back to `js/main.js`, so an app
  can ship plain JavaScript and add a bundler later.
- **Inline `<script>` is blocked** by the Content Security Policy. Behaviour goes in a file.
- The app id, the `<namespace>` in `info.xml` and the `OCA\<Namespace>` PHP namespace must agree, or nothing
  autoloads.
- Nextcloud caches app metadata: after changing `info.xml`, disable and enable the app rather than wondering
  why a navigation entry did not appear.
- In the browser, the app menu is a **popover** whose entries are anchors with `role="menuitem"`, not links.
  Both facts silently break the obvious Playwright locators.

## Files

- [references/php-app-development.md](references/php-app-development.md): structure, scaffold, install,
  verify.
- [references/php-app-ui-testing.md](references/php-app-ui-testing.md): Playwright setup, the four starter
  tests, debugging, and the locator traps.
- [assets/minimal_php_app/](assets/minimal_php_app/): the reference app, including its Playwright suite.
- A development instance to run all this against: [nextcloud-dev-setup](../nextcloud-dev-setup/SKILL.md).
