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

This skill goes from an empty directory to a release tarball in seven stages, each ending with a Verify
block: scaffold and install (1), prove it in a browser (2), store data (3), settings (4), a Vue frontend with
Vite (5), PHP tests, Psalm and code style (6), package and release (7).

## How to work

1. [references/php-app-development.md](references/php-app-development.md): what an app is made of, then the
   seven stages.
2. [assets/minimal_php_app/](assets/minimal_php_app/): the runnable reference app, already at Stage 7. Copy it
   and run its `rename.sh`, rather than assembling files from memory. The plain-JavaScript page works without
   any build; `npm run build` swaps in the Vue frontend behind the same template and tests.
3. [references/php-app-ui-testing.md](references/php-app-ui-testing.md): Playwright against a real Nextcloud,
   including the locator traps that make correct apps look broken.

Verify with commands after every change, cheapest first: `curl` against the route, the PHPUnit suites in the
container, the Playwright suite, a look at the page through a browser tool. Do not move on from a stage whose
Verify block fails. If Vue is required from the start, skip the plain-JavaScript files and write the browser
tests once against the final page; the runbook says how.

## Facts that save hours

- **Routes are deny-by-default.** Without `#[NoAdminRequired]` a route is admin-only; every route needs a
  logged-in user unless it carries `#[PublicPage]`. Anonymous request to a working route: `401`, not `404`.
- **`curl` against your own routes needs `-H 'OCS-APIRequest: true'`**, or even a GET is rejected with
  `412 CSRF check failed`. Inside the page, `@nextcloud/axios` or a `requesttoken` header does the same.
- The app id, `<namespace>` in `info.xml` and the `OCA\<Namespace>` PHP namespace must agree, or nothing
  autoloads. **Rename the reference app with `rename.sh`, not by hand**; it validates and verifies itself.
- **The reference migration runs on the first `occ app:enable`.** Reshape it before enabling if your first
  table differs. Executed migrations are recorded in `oc_migrations` by `(app, version)`: editing one does
  nothing; add a new file, and re-enable the app to run it (`occ app:disable X && occ app:enable X`).
- A column added to an existing table must be nullable or have a real default; a nullable column needs a
  nullable entity property. A column with no entity property makes reads `500` while writes keep working.
- `Util::addScript($appId, $appId . '-main')` resolves `js/<appid>-main.mjs`, then `.js`; `Util::addStyle`
  loads `css/<appid>-main.css`. Inline `<script>` is blocked by the CSP.
- **`npm run build` empties `js/` and `css/`** and writes `<appid>-<entry>.mjs` and `.css` (id from
  `info.xml`); CSS is not inlined into the script. `typescript` and `@nextcloud/browserslist-config` are
  required dev dependencies. Hard-reload after a rebuild: app assets carry far-future cache headers.
- **PHPUnit runs in the Nextcloud container as `www-data`** with the `phpunit` the dev image ships; any other
  user fails with `Cannot write into "config" directory!`. Composer, Psalm and php-cs-fixer run there as
  **your** uid. Target the lowest PHP and Nextcloud you support (8.2, `nextcloud/ocp` `dev-stable33`).
- Release = `make appstore`: schema-checks `info.xml`, builds, tars only what `.nextcloudignore` allows.
  Extract the tarball into another instance and enable it: that is the proof.
- In the browser, the app menu is a **popover** with `role="menuitem"` entries on Nextcloud 34+, inline links
  on 33; **the first-run wizard modal swallows clicks** on fresh instances; some `@nextcloud/vue` inputs
  (`NcCheckboxRadioSwitch`) need their label clicked, not their role. Locate by accessible label and role.
- Give the agent a real browser (an MCP browser server) before writing locators: the accessibility snapshot
  hands you roles and accessible names directly.

## Files

- [references/php-app-development.md](references/php-app-development.md): structure, then the seven stages
  from scaffold to release, each with Verify and If-it-fails blocks.
- [references/php-app-ui-testing.md](references/php-app-ui-testing.md): Playwright setup, the seven starter
  tests, debugging, and the locator traps.
- [assets/minimal_php_app/](assets/minimal_php_app/): the reference app with its Playwright and PHPUnit
  suites, Vue frontend, Psalm and php-cs-fixer configuration and release Makefile. Its
  [README](assets/minimal_php_app/README.md) lists what is where.
- A development instance to run all this against: [nextcloud-dev-setup](../nextcloud-dev-setup/SKILL.md).
