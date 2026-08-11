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
| `appinfo/info.xml` | manifest, navigation entry, settings registration |
| `lib/AppInfo/Application.php` | the bootstrap class |
| `lib/Controller/PageController.php` | a page and a JSON route, with attribute routing and access control |
| `lib/Controller/ItemController.php` | a data API: list and create |
| `lib/Db/Item.php`, `lib/Db/ItemMapper.php` | entity and query-builder data access |
| `lib/Migration/Version1100Date20260811120000.php` | schema migration with an index |
| `lib/Settings/` | admin section and settings form |
| `templates/` | server-rendered pages |
| `js/main.js` | page behaviour in plain JavaScript, no build step |
| `playwright/app.spec.ts` | browser tests covering all of the above |

## Install it

```bash
cp -r minimal_php_app <apps-dir>/<your_app_id>     # apps-extra/ or custom_apps/
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
