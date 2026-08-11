<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Building a Nextcloud PHP app

A detailed runbook, part of the [nextcloud-php-app](../SKILL.md) skill. It starts from an empty directory and
ends with an installed app serving a page, a JSON route and a navigation entry, each step proved by a command.

The reference material for individual APIs (controllers, routing, dependency injection, events, background
jobs, storage) is the
[developer manual](https://docs.nextcloud.com/server/latest/developer_manual/); this runbook is the path
through it, not a replacement for it.

Last verified against: Nextcloud master (35), PHP 8.3, app installed from `apps-extra` on 2026-08-11.

## What an app is made of

| Path | Purpose |
|---|---|
| `appinfo/info.xml` | The manifest: id, version, supported Nextcloud versions, navigation entries, settings |
| `lib/AppInfo/Application.php` | Bootstrap class; registers services and listeners |
| `lib/Controller/` | Controllers; route attributes live on their methods |
| `templates/` | Server-rendered pages returned by a `TemplateResponse` |
| `js/`, `css/`, `img/` | Static assets served under `/apps/<appid>/` |
| `lib/Migration/`, `lib/Db/` | Schema migrations and entities, once the app stores data |

Three names must agree: the **app id** (`minimal_php_app`), the `<namespace>` in `info.xml`
(`MinimalPhpApp`), and the PHP namespace (`OCA\MinimalPhpApp`). Classes under `lib/` autoload from that
namespace; a mismatch produces "class not found" with no other clue.

The `<namespace>` tag is authoritative (`AppManager::getAppNamespace()`); without it the server derives one
by upper-casing the first letter of the app id, which would give the unusable `Minimal_php_app`. That is why
every multi-word app id needs the tag. Within it you are free: `linkstash` may declare either `Linkstash` or
`LinkStash`, as long as the PHP namespace matches exactly.

## Stage 1: scaffold and install

Copy the reference app and rename it, rather than assembling files by hand. `<apps-dir>` is any directory on
the instance's app path: `apps-extra/` in a [nextcloud-docker-dev](../../nextcloud-dev-setup/SKILL.md)
environment, `custom_apps/` on a typical server.

```bash
cp -r <skills-repo>/skills/nextcloud-php-app/assets/minimal_php_app <apps-dir>/<app_id>
cd <apps-dir>/<app_id>
sh rename.sh <app_id> <Namespace> "<Display Name>"
```

Use the script rather than a search-and-replace of your own. Renaming this app by hand is the most
error-prone step in the whole skill, because the identifiers live in three different places: file contents,
file **names**, and a **PHP class name that contains neither the app id nor the namespace**. Miss that last
one and `occ app:enable` dies with `Cannot declare class ... because the name is already in use`; miss the
display strings and your app installs, works, and is called "Minimal PHP App" in the app menu, on its pages
and in the settings list.

The script does all of it, then refuses to finish unless the result is clean: no reference-app strings
anywhere, and every migration class name equal to its filename. It leaves three `TODO` markers in
`appinfo/info.xml` (`<description>`, `<author>`, `<bugs>`) for you to fill in.

Then enable it:

```bash
occ app:enable <app_id>
occ app:list | grep <app_id>
```

Verify:

```bash
# The page: 401 (or a redirect) means the route exists and is protected. 404 means it is not registered.
curl -s -o /dev/null -w "%{http_code}\n" "<nextcloud-url>/index.php/apps/<app_id>/"

# The API route, authenticated:
curl -s -u <user>:<pass> -H 'OCS-APIRequest: true' \
    "<nextcloud-url>/index.php/apps/<app_id>/api/whoami"

# The navigation entry, from the server's own list rather than the rendered page:
curl -s -u <user>:<pass> -H 'OCS-APIRequest: true' \
    "<nextcloud-url>/ocs/v2.php/core/navigation/apps?format=json"
```

Expected: `401` for the anonymous page request, `{"user":"<user>","displayName":"..."}` from the API, and your
app id in the navigation list.

If it fails:

- **404 on the page**: the route attribute is missing, or the controller's namespace does not match
  `<namespace>`. Attribute routes are discovered from `lib/Controller/`.
- **App not in `app:list`**: `info.xml` failed to parse, or its `<dependencies>` exclude this Nextcloud
  version. `occ app:enable` prints the reason.
- **Navigation entry missing**: metadata is cached; `occ app:disable` then `occ app:enable`.

## How the pieces work

### Routes and access control

Routes are PHP attributes on controller methods; `appinfo/routes.php` is the older equivalent and still
works.

```php
#[NoAdminRequired]                              // without this, admin-only
#[NoCSRFRequired]                               // only for routes the browser navigates to directly
#[FrontpageRoute(verb: 'GET', url: '/')]        // /index.php/apps/<appid>/
public function index(): TemplateResponse {
    return new TemplateResponse(Application::APP_ID, 'index');
}
```

The model is deny-by-default: a logged-in user is required unless the method carries `#[PublicPage]`, and
admin rights are required unless it carries `#[NoAdminRequired]`. Put `#[NoCSRFRequired]` only on routes a
browser opens directly; never on one that changes state.

`#[ApiRoute]` (used with `/ocs/`) and `#[FrontpageRoute]` differ in where the route is mounted; both are in
`OCP\AppFramework\Http\Attribute`.

### Dependency injection

Type-hint what you need in the constructor and Nextcloud provides it:

```php
public function __construct(IRequest $request, private IUserSession $userSession) {
    parent::__construct(Application::APP_ID, $request);
}
```

Never reach for `\OC::$server`; anything that is not injectable is not public API. `Application::register()`
runs on **every** request that touches the app, so it must stay cheap: register services and listeners there,
do the work elsewhere.

### Templates and scripts

A `TemplateResponse(APP_ID, 'index')` renders `templates/index.php` inside the Nextcloud page frame. Two rules
decide most of what goes wrong:

- **Escape output** with `p()`, and translate with `$l->t()`.
- **No inline `<script>`**: the Content Security Policy blocks it. Load a file with
  `\OCP\Util::addScript(APP_ID, 'main')`, which resolves `js/main.mjs` first and falls back to `js/main.js`.
  That fallback is what lets an app ship plain JavaScript and adopt a bundler later without changing the PHP.

In plain JavaScript the globals `OC.generateUrl()` and `OC.requestToken` are available, which is enough to
call your own routes without any build tooling.

### Navigation

An entry in `info.xml` puts the app in the app menu:

```xml
<navigations>
    <navigation>
        <id>minimal_php_app</id>
        <name>Minimal PHP App</name>
        <route>minimal_php_app.page.index</route>   <!-- appid.controller.method -->
        <icon>app.svg</icon>
    </navigation>
</navigations>
```

The `<route>` value is `appid.controller.method` with the controller name lowercased and without the
`Controller` suffix. Verify it through the OCS navigation endpoint above rather than by looking at the page:
the menu is rendered client-side, so a missing entry there can mean a rendering problem rather than a
registration problem.

### Calling your own API from the command line

A browser sends the CSRF token automatically; `curl` does not. Without it every request, **including GET**,
is rejected with HTTP `412` and `{"message":"CSRF check failed"}`. Add the header that marks the request as
an API call:

```bash
curl -u <user>:<pass> -H 'OCS-APIRequest: true' "<nextcloud-url>/index.php/apps/<appid>/api/items"
```

This is the single most confusing failure when testing a new route by hand, because it looks like an
authentication problem and is not.

## Stage 2: prove it in a browser

Server-side checks cannot see a script that never loaded, a CSP violation, or a page that renders empty.
Continue with [php-app-ui-testing.md](php-app-ui-testing.md), which sets up Playwright against a real
instance. Add a test per stage from here on; the reference app's suite grows the same way.

## Stage 3: store data

Three pieces: a migration that creates the table, an entity that maps a row, and a mapper that queries it.
See `lib/Migration/`, `lib/Db/` and `lib/Controller/ItemController.php` in the reference app.

**The migration** is a class under `lib/Migration/` named `Version<n>Date<YmdHis>`, where `<n>` is a
zero-padded encoding of the app version (`1.0.0` becomes `1000`, `1.1.0` becomes `1100`). Nextcloud only
orders migrations lexically by that string; it never compares it to `<version>` in `info.xml`.

**A new migration file does not run by itself.** Loading a page or running `occ` will not pick it up. What
runs pending migrations immediately is re-enabling the app:

```bash
occ app:disable <appid> && occ app:enable <appid>
```

That works with or without a version bump (verified: adding a migration to an app whose version stayed at
1.1.0 and re-enabling it created the new index). Bump `<version>` in `info.xml` when you **ship**, because
that is what makes an already-running instance apply the migration on upgrade.

**Executed migrations are remembered, so editing one changes nothing.** Nextcloud records each step as
`(app, version)` in the `oc_migrations` table and skips anything already recorded, no matter what the file
now contains. Re-enabling the app reports success while your schema stays stale, which is a genuinely
confusing failure while iterating on a first migration. Either give the change a **new file** with a
lexically greater version string, or force the recorded one to run again:

```bash
occ migrations:execute <appid> <version>     # e.g. 1000Date20260811150000
```

It prints nothing on success; confirm with the schema export below. Renaming a table this way also leaves the
old table behind: nothing cleans it up for you.

Guard every schema change so re-running the step is harmless, and match the guard to the change: `hasTable()`
before creating a table, and `getTable(...)->hasColumn(...)` before adding a column to an existing one. A
later migration that adds a column passes `hasTable()` trivially and would try to add the column twice. Add
an index on every column you filter by. Index and table names are limited to 30 characters including the `oc_` prefix, so long
app ids force abbreviations; pick names that survive a global search-and-replace when the app is renamed.

**The entity** extends `OCP\AppFramework\Db\Entity`. Column `user_id` becomes property `$userId` with
generated `getUserId()`/`setUserId()`; declare those in `@method` annotations so tooling understands them,
and call `addType()` in the constructor so values come back as `int` or `bool` rather than strings. Booleans
work the same way: `Types::BOOLEAN` in the migration plus `addType('pinned', 'boolean')` round-trips to JSON
`true`/`false`.

**The mapper** extends `QBMapper` and builds queries with the query builder. Bind every value with
`createNamedParameter()`; never concatenate user input into SQL. The table name you pass to the mapper and
create in the migration is **without** the `oc_` prefix (`minimal_php_app_items`); the server adds the
configured prefix, so the real table is `oc_minimal_php_app_items`.

**In the controller**, inject the current user as `private ?string $userId` (lowercase). `$UserId` still
works but has been a deprecated alias since Nextcloud 26.

Verify:

```bash
# the table exists, with its columns and indexes, without needing a database client.
# The export prints ~13 lines per column, so ask for enough context to see them all.
occ db:schema:export | grep -A60 "oc_<appid>_<table>"
# create and list through the API
curl -u <user>:<pass> -H 'OCS-APIRequest: true' -H 'Content-Type: application/json' \
    -X POST "<nextcloud-url>/index.php/apps/<appid>/api/items" -d '{"title":"first item"}'
curl -u <user>:<pass> -H 'OCS-APIRequest: true' "<nextcloud-url>/index.php/apps/<appid>/api/items"
```

Expected: `201` with the created row, then a list containing it. A `400` for an empty title proves the
controller's validation runs.

If it fails:

- **Table missing**: in order of likelihood: you did not re-enable the app after adding the migration
  (`occ app:disable <appid> && occ app:enable <appid>`); you **edited an already-executed migration** instead
  of adding a new one (see the ledger note above); or the migration's class name does not match its filename,
  in which case `occ app:enable` fataled and the app is half-installed.
- **`Class not found`**: the migration's namespace must match `OCA\<Namespace>\Migration`.
- **A property with no matching column** is silently ignored when writing.
- **A column with no matching entity property is the opposite of silent**, and it is the one that actually
  happens: you add a column in a migration and forget the entity. `select('*')` maps every column through a
  setter, so **reads** throw `<propertyName> is not a valid attribute` and the route returns `500`, while
  writes keep working. Add the property and its `addType()` in the same change as the migration.
- `occ migrations:status <appid>` reports odd counters ("Executed Unavailable: 1", "New Migrations: 1") on a
  perfectly healthy app; do not chase them. The schema export is the reliable check.

## Stage 4: settings

Two classes and a template: a **section** (`IIconSection`) is the entry in the settings list, a **settings**
class (`ISettings`) is the form inside it, and both are registered in `info.xml`:

```xml
<settings>
    <admin>OCA\MinimalPhpApp\Settings\AdminSettings</admin>
    <admin-section>OCA\MinimalPhpApp\Settings\AdminSection</admin-section>
</settings>
```

Pass values to the frontend with `IInitialState::provideInitialState()` rather than printing them into the
template: the frontend reads them as parsed JSON, and nothing lands in the HTML. Store configuration with
`IAppConfig` (`getValueString`, `setValueString`), which is the supported replacement for the old
`IConfig::getAppValue` calls.

Personal settings work identically with `<personal>` and `<personal-section>`.

Verify: open `<nextcloud-url>/index.php/settings/admin/<appid>`; the section appears in the left-hand list
and the form renders. The reference app asserts exactly that in its Playwright suite.

## Related

- [php-app-ui-testing.md](php-app-ui-testing.md): browser verification.
- [nextcloud-dev-setup](../../nextcloud-dev-setup/SKILL.md): an instance to develop against.
- [exapp-development](../../exapp-development/SKILL.md): when the code should run in its own container
  instead.
- Developer manual: [app development](https://docs.nextcloud.com/server/latest/developer_manual/).
