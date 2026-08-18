<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Building a Nextcloud PHP app

A detailed runbook, part of the [nextcloud-php-app](../SKILL.md) skill. It starts from an empty directory and
ends with a released tarball: an installed app serving a page, a JSON route and a navigation entry, then
data, settings, a Vue frontend, PHP tests, static analysis and packaging, each step proved by a command.

The reference material for individual APIs (controllers, routing, dependency injection, events, background
jobs, storage) is the
[developer manual](https://docs.nextcloud.com/server/latest/developer_manual/); this runbook is the path
through it, not a replacement for it.

Last verified against: Nextcloud master (35), 34.0.2 and 33.0.7 with PHP 8.3, Node 22, Vite 7.3,
@nextcloud/vue 9.9, PHPUnit 11.5, Psalm 6.16, app installed from `apps-extra` (and, on 33, from its own
release tarball) on 2026-08-18.

## What an app is made of

| Path | Purpose |
|---|---|
| `appinfo/info.xml` | The manifest: id, version, supported Nextcloud versions, navigation entries, settings |
| `lib/AppInfo/Application.php` | Bootstrap class; registers services and listeners |
| `lib/Controller/` | Controllers; route attributes live on their methods |
| `templates/` | Server-rendered pages returned by a `TemplateResponse` |
| `js/`, `css/`, `img/` | Static assets served under `/apps/<appid>/`; `js/` and `css/` are the Vite build output once you build |
| `lib/Migration/`, `lib/Db/` | Schema migrations and entities, once the app stores data |
| `lib/Settings/` | Admin or personal settings section and form |
| `lib/Service/` | Logic shared by controllers, when it appears; any `lib/<Dir>/` autoloads as `OCA\<Namespace>\<Dir>` |
| `src/`, `vite.config.js`, `package.json` | The Vue frontend and its build (Stage 5) |
| `tests/`, `composer.json`, `psalm.xml`, `.php-cs-fixer.dist.php` | PHPUnit suites, static analysis, code style (Stage 6) |
| `.nextcloudignore`, `krankerl.toml`, `Makefile` | What goes into the release tarball, and how to build it (Stage 7) |

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

**Decide about the reference table before the first enable.** The copy carries a migration that creates
`<prefix>_items(id, user_id, title, created_at)`, the first `occ app:enable` runs it, and executed migrations
are frozen from then on (Stage 3 explains the ledger). So if your app's first table is not that one, either
reshape `lib/Migration/Version1000Date*.php`, `lib/Db/Item*.php` and `ItemController.php` **now**, following
the rules in Stage 3, or accept that your own tables arrive in a second migration and drop the reference
table there (`$schema->dropTable('<prefix>_items')`) once nothing uses it. Editing the reference migration
after it ran changes nothing.

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

Expected: `401` for the anonymous page request, `{"user":"<user>","displayName":"..."}` from the API (or
whatever your own first JSON route answers, if you replaced `whoami`), and your app id in the navigation list.

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

A `TemplateResponse(APP_ID, 'index')` renders `templates/index.php` inside the Nextcloud page frame. Three
rules decide most of what goes wrong:

- **Escape output** with `p()`, and translate with `$l->t()`.
- **No inline `<script>`**: the Content Security Policy blocks it. Load a file with
  `\OCP\Util::addScript(APP_ID, APP_ID . '-main')`, which resolves `js/<appid>-main.mjs` first and falls
  back to `js/<appid>-main.js`; `\OCP\Util::addStyle(APP_ID, APP_ID . '-main')` loads
  `css/<appid>-main.css`. Those are exactly the names the Vite build writes (Stage 5), so the same template
  serves the plain-JavaScript stages and the built app.
- **Wrap the page in `<div id="app-content">`**: that id is the server's hook for the white main panel and
  its scrolling. Without it your markup renders straight onto the background image. (A page that is entirely
  Vue uses `NcContent` and `NcAppContent` instead, which draw that frame themselves; then the template is a
  single empty `<div id="<appid>">` and no wrapper is needed. See the end of Stage 5.)

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
instance. Add a test per stage from here on; the reference app's suite grows the same way (seven tests by
the end of this runbook), and it does not change when the frontend is swapped in Stage 5.

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
an index on every column you filter by. Index and table names are limited to 30 characters including the
`oc_` prefix, so long app ids force abbreviations; pick names that survive a global search-and-replace when
the app is renamed.

A column **added to an existing table** must be nullable or carry a real default: the server refuses a
`NOT NULL` column whose default is the empty string with `Column "..." is NotNull, but has empty string or null
as default.` (`MigrationService::ensureOracleConstraints`, because null and `''` are the same thing on
Oracle), and the database itself refuses `NOT NULL` without a default when rows exist. Match the entity to
that: a nullable column needs a nullable typed property (`protected ?string $url = null`), because the
generated setter assigns the database value straight into the property and `null` into `string` is a
`TypeError` at read time.

**Uniqueness** is a database job: `$table->addUniqueIndex(['user_id', 'note_date'], '<prefix>_notes_ud')`
in the migration, and in the code that inserts, catch `OCP\DB\Exception` and check
`$e->getReason() === \OCP\DB\Exception::REASON_UNIQUE_CONSTRAINT_VIOLATION` to turn the race into an
update or a `409`; the reason code is what lets you tell it apart from any other database error, and it is
what a unit test mocks. (`db:schema:export` prints `unique: true` under the index.)

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
# The export prints ~13 lines per column, so ask for enough context to see them all;
# add `| grep -E "name:|unique:|notnull:"` when you only want the shape at a glance.
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

Two classes, a template, a script and a route. A **section** (`IIconSection`) is the entry in the settings
list, a **settings** class (`ISettings`) is the form inside it, and both are registered in `info.xml`:

```xml
<settings>
    <admin>OCA\MinimalPhpApp\Settings\AdminSettings</admin>
    <admin-section>OCA\MinimalPhpApp\Settings\AdminSection</admin-section>
</settings>
```

The value makes a round trip, and the reference app shows every leg of it:

- **Out**: `AdminSettings::getForm()` reads it with `IAppConfig` (`getValueString`; `getValueInt`,
  `getValueBool` and `getValueArray` exist for other types, all the supported replacement for the old
  `IConfig::getAppValue`), hands it to the frontend with `IInitialState::provideInitialState()`, and loads the
  form's script with `Util::addScript(APP_ID, APP_ID . '-admin')` (plus `Util::addStyle`). Nothing is
  printed into `templates/admin.php`; the template is the empty form.
- **In the browser**: the script reads it back with `OCP.InitialState.loadState(APP_ID, 'greeting')` in
  plain JavaScript (`js/<appid>-admin.js`) or `loadState()` from `@nextcloud/initial-state` in Vue
  (`src/AdminSettings.vue`, the second Vite entry of Stage 5). No GET route is needed for that.
- **Back**: the save is a `PUT /api/settings` to `SettingsController::update()`, which carries **no**
  `#[NoAdminRequired]`: deny-by-default makes it admin-only, and it writes with `setValueString`.

Personal settings work identically with `<personal>` and `<personal-section>` (and `IUserConfig` or
`IConfig::getUserValue` for per-user values).

Verify:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -H 'OCS-APIRequest: true' -H 'Content-Type: application/json' \
    -X PUT "<nextcloud-url>/index.php/apps/<appid>/api/settings" -d '{"greeting":"x"}'          # 401
curl -u <admin>:<pass> -H 'OCS-APIRequest: true' -H 'Content-Type: application/json' \
    -X PUT "<nextcloud-url>/index.php/apps/<appid>/api/settings" -d '{"greeting":"Hey"}'        # {"greeting":"Hey"}
occ config:app:get <appid> greeting                                                             # Hey
```

A non-admin user gets `403` on the same request. Then open `<nextcloud-url>/index.php/settings/admin/<appid>`:
the section appears in the left-hand list, the field shows the stored value, and saving reports back. The
reference app's fifth Playwright test does exactly that, including a reload to prove the value was stored
rather than echoed.

## Stage 5: a Vue frontend with Vite

Plain JavaScript carries an app a long way, and it is the right way to start: nothing to install, nothing to
build, and the page is already testable. Switch when the UI grows, or when you want the components users
already know from Nextcloud (`@nextcloud/vue`: text fields, buttons, dialogs, the app frame). The reference
app ships both frontends behind the same template and the same tests, so the switch is one command.

What the switch consists of (all in the reference app):

- `package.json`: `vue`, `@nextcloud/vue`, `@nextcloud/axios`, `@nextcloud/router`, `@nextcloud/l10n` as
  dependencies; `vite`, `@nextcloud/vite-config`, **`typescript` and `@nextcloud/browserslist-config`** as
  dev dependencies, plus `"browserslist": ["extends @nextcloud/browserslist-config"]`. The last two are not
  optional even for a JavaScript-only app: `@nextcloud/vite-config` loads them at config time and fails
  without them (`Cannot read properties of undefined (reading 'useCaseSensitiveFileNames')` for a missing
  `typescript`, `Cannot find module '@nextcloud/browserslist-config'` for the other).
- `vite.config.js`: `createAppConfig({ main: 'src/main.js', admin: 'src/admin.js' })` from
  `@nextcloud/vite-config`. **One entry per script Nextcloud loads**: the page and the admin form here, one
  more for every further page, settings form or files-app plugin. The output name is
  `js/<appid>-<entry>.mjs`, with `<appid>` read from `appinfo/info.xml`, and the entry's CSS goes to
  `css/<appid>-<entry>.css` (CSS is **not** inlined into the script by default, which is why the PHP also
  calls `Util::addStyle`; the entry CSS `@import`s the shared chunk CSS, so one `addStyle` per entry is
  enough). Shared code lands in a `*.chunk.mjs` that the entries import.
- `src/main.js` mounts `src/App.vue` on the `<div id="<appid>">` the template already renders;
  `src/admin.js` mounts `src/AdminSettings.vue` on the admin form's wrapper. The components use
  `NcTextField` and `NcButton` from `@nextcloud/vue/components/...`, `t()` from `@nextcloud/l10n`,
  `generateUrl()` from `@nextcloud/router`, `loadState()` from `@nextcloud/initial-state`, and
  `@nextcloud/axios`, which sends the CSRF token on every request so the routes keep their protection.

```bash
npm ci               # about 300 MB of node_modules, once; needs Node 20.19+
npm run build        # about a second; `npm run watch` rebuilds on change
```

**The build empties `js/` and `css/` first** (`emptyOutputDirectory`, with `css` added in the reference
config), then writes the built files under the same names the plain files had. That is deliberate: the
PHP does not change, `Util::addScript` now finds the `.mjs`, and the plain script is gone. There is no going
back except through git, so if you want to keep the plain frontend, do not build.

If Vue is a given from the start, do not write the plain frontend twice: delete `js/*.js` and `css/*.css`
after renaming (and then either ignore `js/` and `css/` entirely in `.gitignore` or commit the build output;
the reference `.gitignore` tracks the plain files and ignores the built ones, which stops making sense once
the plain files are gone), build the backend (Stages 3 and 4, verified with `curl`), then the Vue frontend,
then write the Playwright suite once against the final page. The stage order above is the learning order,
not a requirement; two fresh agents that did exactly this delivered complete apps in eleven and twelve
minutes.

The components' TypeScript declarations do not list their props (`DefineSetupFnComponent<Record<string,
any>>`), so the reference and the two snippets below are the documentation an agent actually has:

```vue
<NcTextField v-model="title" :label="t(APP_ID, 'New item')" />           <!-- text input -->
<NcCheckboxRadioSwitch v-model="teamVisible" type="switch"                <!-- on/off switch -->
    @update:model-value="save">
    {{ t(APP_ID, 'Notes are visible to the whole team') }}
</NcCheckboxRadioSwitch>
```

`v-model` is the value, `type="switch"` makes a checkbox a switch, the slot is the label, and
`@update:model-value` fires on change; import from `@nextcloud/vue/components/NcCheckboxRadioSwitch`. Full
component list and props: https://nextcloud-vue-components.netlify.app/.

Two warnings are normal and can be ignored: `build.outDir must not be the same directory of root` (Nextcloud
apps build into their own directory on purpose) and, when the app lives inside a server checkout, an esbuild
note about the server's `tsconfig.json`, which the app's own `package.json` browserslist entry is there to
neutralise (config lookup walks up the directory tree, and the server has both files).

Verify:

```bash
ls js css                                     # <appid>-main.mjs, <appid>-main.css, a *.chunk.css
PLAYWRIGHT_BASE_URL=<nextcloud-url> npm run playwright   # the same 7 tests pass unchanged
```

Then look at the page: the text field and button are the Nextcloud components. **Reload with the cache
disabled** (hard reload, or a browser tool's reload with `ignoreCache`): the web server sends far-future
cache headers for app assets, so a normal reload after a rebuild can show you the previous build. Playwright
and the MCP browser tool open fresh contexts and are unaffected.

If it fails:

- **`npm run build` fails at config load** with one of the two errors quoted above: add the missing dev
  dependency.
- **The page still shows the old frontend**: cache; hard reload. If `ls js` shows only `.js`, the build did
  not run.
- **Components render unstyled** (no border on the field, text overflowing the button): `Util::addStyle` is
  missing from the template, or its name does not match `css/<appid>-main.css`.
- **The Playwright suite fails on the "adding an item" test only**: your locators are tied to the plain
  DOM. Locate by accessible label and role (`getByLabel('New item')`, `getByRole('button', { name: 'Add' })`),
  which the plain `<input aria-label>` and the `NcTextField` component both satisfy.

Going further: when the whole page is Vue, shrink the template to a single empty `<div id="<appid>">` and let
`NcContent` and `NcAppContent` from `@nextcloud/vue` draw the app frame; that is what shipped apps such as
activity do (`templates/index.php` is one line, the layout lives in `src/views/`).

## Stage 6: PHP tests, static analysis, code style

The reference app carries two PHPUnit suites, and one bootstrap that serves both:

- **`tests/unit/`**: plain `PHPUnit\Framework\TestCase`, dependencies mocked. `ItemControllerTest` builds
  the controller by hand with a mocked mapper and asserts validation and response shapes. Runs anywhere.
- **`tests/integration/`**: `\Test\TestCase` from the server checkout, real database.
  `ItemMapperTest` gets the mapper from the container (`Server::get(ItemMapper::class)`), inserts rows for two
  users, asserts the filter and that `addType()` gives back an `int`, and deletes what it created. It is
  tagged `#[Group('DB')]` (the attribute; a `@group` docblock is a PHPUnit 11 deprecation).
- **`tests/bootstrap.php`** looks for `../../../tests/bootstrap.php`. If the app sits inside a Nextcloud
  checkout (`apps/`, `apps-extra/`, `custom_apps/`), it boots the server, so both suites can run. Otherwise
  it loads `vendor/autoload.php`, which is enough for the unit suite because `composer.json` maps `OCP\` to
  the `nextcloud/ocp` package in `autoload-dev` (that package ships no autoloader of its own; it exists for
  static analysis).

**Run inside the container**, as the web server user, and nothing needs installing: the
nextcloud-docker-dev image ships `phpunit` (11.5, a phar in `/usr/local/bin`) and the server checkout
provides `\Test\TestCase`:

```bash
docker exec -u www-data -w /var/www/html/apps-extra/<appid> <nextcloud-container> \
    phpunit -c tests/phpunit.xml                    # both suites
docker exec -u www-data -w /var/www/html/apps-extra/<appid> <nextcloud-container> \
    phpunit -c tests/phpunit.xml --testsuite unit   # or: --filter ItemMapperTest
```

`www-data` is not a style choice: the server bootstrap reads `config/config.php`, and any other user is
answered with `Cannot write into "config" directory!` or `Not installed`. Because that user cannot write
into the mounted app directory, `tests/phpunit.xml` sets `cacheResult="false"`; without it every run ends
with `Permission denied` on `.phpunit.result.cache`.

**Static analysis and code style** need Composer dependencies. Install and run them in the container as
**your own uid**, so `vendor/` belongs to you and the checks see the container's PHP (Psalm 6 refuses PHP
below 8.3.16, which rules out the stock PHP of Ubuntu 24.04 on the host):

```bash
X="docker exec -u $(id -u):$(id -g) -w /var/www/html/apps-extra/<appid> <nextcloud-container>"
$X composer install
$X vendor/bin/psalm --no-cache                     # "No errors found!"
$X vendor/bin/php-cs-fixer fix --dry-run --diff    # "Found 0 of N files that can be fixed"
$X vendor/bin/php-cs-fixer fix                     # or apply the fixes
```

Standalone (the app in its own repository, no server around, PHP 8.3+ on the host): `composer install`, then
`vendor/bin/phpunit -c tests/phpunit.xml --testsuite unit`. The integration suite is not runnable there;
that is what CI does by checking out the server first, the way every app in the Nextcloud organisation
does.

Three things Psalm taught the reference app, worth knowing before it teaches you:

- **A docblock line that starts with `@method` is parsed as a declaration.** A sentence in the class
  comment that began "`@method` annotations are what ...", wrapped so that the tag started the line, made the
  whole docblock invalid and every generated accessor "undefined". Keep the tag out of prose.
- Psalm 6 wants `#[\Override]` on every implemented method and `final` on every class; the server and its
  apps suppress both (`MissingOverrideAttribute`, `ClassMustBeFinal`), and so does `psalm.xml` here.
- `phpVersion` in `psalm.xml` must be the **lowest** PHP you support, not the one you run: with `8.3` Psalm
  demands typed class constants, which fatal on the PHP 8.2 that Nextcloud 33 and 34 still accept. The
  reference declares `<php min-version="8.2"/>` in `info.xml`, `"php": ">=8.2"` in `composer.json` and
  `phpVersion="8.2"` in `psalm.xml`, one fact in three places.

Verify: `OK (6 tests, 23 assertions)` from the container run, `No errors found!` from Psalm, `Found 0 of N
files that can be fixed` from php-cs-fixer, and `OK (5 tests, 19 assertions)` from a standalone unit run.

If it fails:

- **`Class "Test\TestCase" not found`**: the integration suite ran without a server checkout. Run it in
  the container, or `--testsuite unit`.
- **`Class "OCP\...\QBMapper" not found` in a standalone run**: `composer dump-autoload` after copying
  `composer.json`; the `OCP\` mapping in `autoload-dev` is what provides it.
- **`Not installed` or `Cannot write into "config" directory!`**: wrong user, see above.
- **`Metadata found in doc-comment ... deprecated`**: a `@group` or `@dataProvider` docblock; use the
  attribute.
- **Psalm reports dozens of `UndefinedMagicMethod` on an entity**: the docblock trap above; check that no
  prose line starts with `@method`.

## Stage 7: package and release

An app is released as a tarball whose top-level directory is the app id, containing only what runs:
`appinfo/`, `lib/`, `templates/`, `img/`, `l10n/`, the **built** `js/` and `css/` (source maps included, as
the apps in the Nextcloud organisation ship them; add `/js/*.map` to the ignore list if you would rather
not). Sources, tests, tooling and `node_modules/` stay out. The reference app declares that list once, in
`.nextcloudignore` (gitignore syntax), and offers two ways to apply it:

- **`make appstore`**: validates `appinfo/info.xml` against the app store schema, runs `npm ci && npm run
  build`, copies everything not ignored into `build/<appid>/` and writes
  `build/artifacts/<appid>-<version>.tar.gz`. Needs `xmllint` (`libxml2-utils` on Debian and Ubuntu,
  preinstalled on macOS), `rsync` and `tar`.
- **`krankerl package`**, the community tool that reads the same `.nextcloudignore` and the `before_cmds`
  in `krankerl.toml`.

The manifest check is a real gate: after `rename.sh`, `<bugs>TODO your issue tracker</bugs>` fails it with
`[facet 'pattern'] The value 'TODO your issue tracker' is not accepted by the pattern 'https?://.+'`, so a
release cannot ship the placeholders.

Verify, the way a user would install it:

```bash
make appstore
tar -tzf build/artifacts/<appid>-<version>.tar.gz    # reference app: 27 entries, no src/ tests/ vendor/ node_modules/
# on another instance (or after moving the dev copy aside):
tar -xzf build/artifacts/<appid>-<version>.tar.gz -C <apps-dir>
occ app:enable <appid>
```

The reference app's tarball, extracted into a Nextcloud 33 instance, enabled and passed its full Playwright
suite: that is the check that the ignore list did not drop anything the app needs at runtime.

Before each release, bump `<version>` in `info.xml`: that is what makes running instances apply new
migrations on upgrade (Stage 3), and the app store rejects a version it has seen. Publishing to the app
store itself, signing the tarball with `occ integrity:sign-app` and the certificate you receive when the app
is registered, and uploading it, is described in the
[publishing guide](https://docs.nextcloud.com/server/latest/developer_manual/app_publishing_maintenance/publishing.html);
it needs an app store account and was not part of this verification.

## Related

- [php-app-ui-testing.md](php-app-ui-testing.md): browser verification.
- [nextcloud-dev-setup](../../nextcloud-dev-setup/SKILL.md): an instance to develop against.
- [exapp-development](../../exapp-development/SKILL.md): when the code should run in its own container
  instead.
- Developer manual: [app development](https://docs.nextcloud.com/server/latest/developer_manual/).
