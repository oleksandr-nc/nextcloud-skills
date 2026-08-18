---
name: nextcloud-php-app
description: >-
  Builds a Nextcloud app in PHP, the kind that runs inside the Nextcloud process, from an empty directory to a
  release tarball: manifest and bootstrap class, attribute routes, templates and page scripts, navigation,
  database migrations and entities, admin settings, a Vue and Vite frontend, PHPUnit, Psalm and php-cs-fixer,
  packaging, and browser-level verification with Playwright against a real instance. Use when creating a
  Nextcloud app, adding a page, route, table or settings section to one, or setting up tests and a release for
  it. For services that run in their own container, use exapp-development instead.
license: AGPL-3.0-or-later
compatibility: >-
  Nextcloud 33, 34 or 35 with a development instance and shell access; the Vue build and Playwright need Node
  20.19+. Last verified with Nextcloud master (35), 34.0.2 and 33.0.7, PHP 8.3, Playwright 1.62, Vite 7.3,
  PHPUnit 11.5.
---

# Nextcloud PHP apps

A PHP app runs **inside** Nextcloud: same process, same request, direct access to the server's APIs through
dependency injection. That makes it the right choice for UI, routes, settings, storage and events, and the
wrong choice for anything long-running or written in another language, which belongs in an
[ExApp](../exapp-development/SKILL.md).

This skill goes from an empty directory to a release tarball, in seven stages that each end with a Verify
block: scaffold and install (1), prove it in a browser (2), store data (3), settings (4), a Vue frontend with
Vite (5), PHP tests, Psalm and code style (6), package and release (7). Every stage was executed against live
Nextcloud 33, 34 and 35 instances, and by fresh agents who had only this guide.

## How to work

1. [references/php-app-development.md](references/php-app-development.md): what an app is made of, then the
   seven stages, each installed and verified on a real instance.
2. [assets/minimal_php_app/](assets/minimal_php_app/): the runnable reference app, already at Stage 7. Copy it
   and run its `rename.sh`, rather than assembling files from memory; the plain-JavaScript page works without
   any build, and `npm run build` swaps in the Vue frontend behind the same template and tests.
3. [references/php-app-ui-testing.md](references/php-app-ui-testing.md): Playwright against a real Nextcloud,
   including the locator traps that make correct apps look broken.

Verify with commands after every change, in this order of cost: `curl` against the route, the PHPUnit suites
in the container, the Playwright suite, and a look at the page through a browser tool. Do not move on from a
stage whose Verify block fails.

## Facts that save hours

- **Routes are deny-by-default.** Without `#[NoAdminRequired]` a route is admin-only, and every route needs a
  logged-in user unless it carries `#[PublicPage]`. An unauthenticated request to a working route answers
  `401`, not `404`: use that to tell "route missing" from "route protected".
- `Util::addScript($appId, $appId . '-main')` looks for `js/<appid>-main.mjs` first and falls back to
  `js/<appid>-main.js`, so an app can ship plain JavaScript and adopt the Vite build later without touching
  the PHP; the reference app does exactly that.
- **Inline `<script>` is blocked** by the Content Security Policy. Behaviour goes in a file.
- The app id, the `<namespace>` in `info.xml` and the `OCA\<Namespace>` PHP namespace must agree, or nothing
  autoloads.
- **`curl` against your own routes needs `-H 'OCS-APIRequest: true'`**, otherwise even a GET is rejected with
  `412 CSRF check failed`, which looks like an auth problem and is not.
- **Rename the reference app with its `rename.sh`, not by hand.** A migration's class name contains neither
  the app id nor the namespace, so hand renames fatal on install; display strings are a third set again.
- Executed migrations are recorded in `oc_migrations` by `(app, version)`: **editing one does nothing**, for
  ever. Add a new file, or force it with `occ migrations:execute <appid> <version>`.
- A new migration file runs when you **re-enable the app** (`occ app:disable X && occ app:enable X`),
  with or without a version bump. Bump `<version>` for shipping, so running instances apply it on upgrade.
- Inject the current user as `$userId` (lowercase); `$UserId` is a deprecated alias.
- Nextcloud caches app metadata: after changing `info.xml`, disable and enable the app rather than wondering
  why a navigation entry did not appear.
- **`npm run build` empties `js/` and `css/`** and writes `js/<appid>-<entry>.mjs` plus
  `css/<appid>-<entry>.css` (the app id read from `info.xml`). CSS is not inlined into the script, so the
  template needs `Util::addStyle` next to `Util::addScript`. `typescript` and `@nextcloud/browserslist-config`
  are required dev dependencies even for a JavaScript-only app.
- After a rebuild, **hard-reload**: app assets are served with far-future cache headers, so a plain reload can
  show the previous build.
- **PHPUnit runs in the Nextcloud container as `www-data`**, with the `phpunit` the dev image ships and the
  server's own bootstrap; any other user fails with `Cannot write into "config" directory!`. Composer, Psalm
  and php-cs-fixer run in the same container as **your** uid so `vendor/` stays yours.
- **A docblock line starting with `@method` is a declaration** to Psalm; a wrapped sentence that begins with
  the tag invalidates the whole entity docblock and every accessor becomes "undefined".
- Target the **lowest** PHP you support (8.2 for Nextcloud 33 and 34) in `psalm.xml`, `info.xml` and
  `composer.json`; Psalm on 8.3 asks for typed constants that fatal on 8.2.
- Release = `make appstore`: schema-checks `info.xml` (fails on `rename.sh`'s TODO placeholders), builds,
  and tars only what `.nextcloudignore` allows. Extract the tarball into another instance and enable it: that
  is the proof.
- In the browser, the app menu is a **popover** whose entries are anchors with `role="menuitem"` on Nextcloud
  34 and later; on 33 it is inline in the header with plain links. Both facts silently break the obvious
  Playwright locators.
- **The first-run wizard modal swallows clicks** on a fresh instance: read-only assertions pass, clicks time
  out. Dismiss it per user before interacting (`DELETE /apps/firstrunwizard/wizard`).
- Give the agent a real browser (an MCP browser server) before writing locators: the accessibility snapshot
  hands you roles and accessible names directly, and the traps above become obvious.

## Files

- [references/php-app-development.md](references/php-app-development.md): structure, then the seven stages
  from scaffold to release, each with Verify and If-it-fails blocks.
- [references/php-app-ui-testing.md](references/php-app-ui-testing.md): Playwright setup, the seven starter
  tests, debugging, and the locator traps.
- [assets/minimal_php_app/](assets/minimal_php_app/): the reference app, including its Playwright and PHPUnit
  suites, Vue frontend, Psalm and php-cs-fixer configuration and release Makefile. Its
  [README](assets/minimal_php_app/README.md) lists what is where; read it before copying.
- A development instance to run all this against: [nextcloud-dev-setup](../nextcloud-dev-setup/SKILL.md).
