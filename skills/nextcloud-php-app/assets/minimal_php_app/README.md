<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# minimal_php_app

The reference app for the [nextcloud-php-app](../../SKILL.md) skill: the smallest Nextcloud app that still
shows every moving part. Copy it, rename it, and grow it.

## What it contains

| Path | Shows |
|---|---|
| `appinfo/info.xml` | manifest, navigation entry, settings registration, PHP and Nextcloud version range |
| `lib/AppInfo/Application.php` | the bootstrap class |
| `lib/Controller/PageController.php` | a page and a JSON route, with attribute routing and access control |
| `lib/Controller/ItemController.php` | a data API: list and create |
| `lib/Controller/SettingsController.php` | an admin-only route that stores the admin setting |
| `lib/Db/Item.php`, `lib/Db/ItemMapper.php` | entity and query-builder data access |
| `lib/Migration/Version1100Date20260811120000.php` | schema migration with an index |
| `lib/Settings/` | admin section and settings form (initial state out, PUT route back) |
| `templates/` | server-rendered pages; `index.php` loads `<appid>-main` script and style |
| `js/minimal_php_app-*.js`, `css/minimal_php_app-*.css` | the page and the admin form in plain JavaScript, no build step |
| `src/`, `vite.config.js` | the same page and form in Vue with `@nextcloud/vue`, two Vite entries; `npm run build` replaces the plain files |
| `playwright/app.spec.ts` | 7 browser tests covering all of the above, passing against both frontends |
| `tests/unit/`, `tests/integration/`, `tests/phpunit.xml` | PHPUnit: mocked controller tests, real-database mapper test |
| `composer.json`, `psalm.xml`, `.php-cs-fixer.dist.php` | dev dependencies, static analysis, code style |
| `.nextcloudignore`, `krankerl.toml`, `Makefile` | release packaging (`make appstore`) |

## Install it

```bash
cp -r minimal_php_app <apps-dir>/minimal_php_app     # apps-extra/ or custom_apps/
occ app:enable minimal_php_app
```

Verify:

```bash
# route exists and is protected (401, not 404)
curl -s -o /dev/null -w "%{http_code}\n" "<nextcloud-url>/index.php/apps/minimal_php_app/"
# the data API (the OCS-APIRequest header is what satisfies the CSRF check for curl)
curl -u <user>:<pass> -H 'OCS-APIRequest: true' -H 'Content-Type: application/json' \
    -X POST "<nextcloud-url>/index.php/apps/minimal_php_app/api/items" -d '{"title":"first item"}'
```

## Run the browser tests

```bash
npm install
npm run playwright:install
PLAYWRIGHT_BASE_URL=<nextcloud-url> npm run playwright
```

The suite logs in through the real form, so it needs a user; it defaults to `admin`/`admin` and reads
`NEXTCLOUD_USER` / `NEXTCLOUD_PASSWORD` when set.

## Build the Vue frontend

```bash
npm ci && npm run build          # writes js/minimal_php_app-main.mjs and css/, removing the plain files
```

The template does not change: `Util::addScript` picks the `.mjs` up. The Playwright suite passes unchanged.

## Run the PHP tests and checks

Inside the Nextcloud container (`<dir>` is the app directory as the container sees it, e.g.
`/var/www/html/apps-extra/minimal_php_app`):

```bash
docker exec -u www-data -w <dir> <nextcloud-container> phpunit -c tests/phpunit.xml
X="docker exec -u $(id -u):$(id -g) -w <dir> <nextcloud-container>"
$X composer install && $X vendor/bin/psalm --no-cache && $X vendor/bin/php-cs-fixer fix --dry-run --diff
```

## Package it

```bash
make appstore                    # build/artifacts/minimal_php_app-<version>.tar.gz
```

## Renaming it for your own app

```bash
sh rename.sh <app_id> <Namespace> "<Display Name>"
# example: sh rename.sh snippetbox SnippetBox "Snippet Box"
```

Do not do this by hand. The identifiers live in file contents, in file names, and in a migration **class
name that contains neither the app id nor the namespace** - miss that one and `occ app:enable` fatals with
`Cannot declare class ...`. Display strings ("Minimal PHP App", the summary, the author, the bugs URL) are a
separate set again, and missing them gives you a working app called "Minimal PHP App" in the app menu.

The script renames identifiers, display strings, the migration file and its class, the spec file and the
table and index names (shortened to fit the 30-character limit), resets the version to 1.0.0, deletes this
README and itself, and then **fails** unless the result is clean: no reference-app strings left, and every
migration class name equal to its filename. It leaves `TODO` markers in `appinfo/info.xml` for
`<description>`, `<author>` and `<bugs>`.
