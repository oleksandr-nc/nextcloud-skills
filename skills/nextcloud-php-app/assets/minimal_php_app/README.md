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

Two substitutions plus two file renames cover everything. Run them from inside your copy:

```bash
rm -rf node_modules test-results playwright-report
grep -rIl 'minimal_php_app\|MinimalPhpApp' . --exclude-dir=node_modules | xargs sed -i \
    -e 's/minimal_php_app/<app_id>/g' -e 's/MinimalPhpApp/<Namespace>/g'
mv lib/Migration/Version1100Date20260811120000.php lib/Migration/Version1000Date<YmdHis>.php
mv playwright/app.spec.ts playwright/<app_id>.spec.ts
grep -rn 'minimal\|MinimalPhp' . --exclude-dir=node_modules      # must print nothing
```

What those two substitutions actually reach, so you can check the result: the directory name, `<id>`,
`<namespace>`, the navigation route and settings class names in `info.xml`; every PHP namespace and class
reference; the **database table name** (`minimal_php_app_items`) in both the migration and the mapper; the
**index name**; the `data-testid` values and URLs in the templates, JavaScript and specs; and `name` in
`package.json`. The migration class name is inside the file as well as in its filename, which is why the
`mv` is followed by the final grep.
