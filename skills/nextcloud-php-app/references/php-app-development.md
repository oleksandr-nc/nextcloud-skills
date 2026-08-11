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

## Stage 1: scaffold and install

Copy the reference app and rename it, rather than assembling files by hand:

```bash
cp -r <skills-repo>/skills/nextcloud-php-app/assets/minimal_php_app <apps-dir>/<your_app_id>
```

`<apps-dir>` is any directory on the instance's app path: `apps-extra/` in a
[nextcloud-docker-dev](../../nextcloud-dev-setup/SKILL.md) environment, `custom_apps/` on a typical server.

Then enable it:

```bash
occ app:enable minimal_php_app
occ app:list | grep minimal_php_app
```

Verify:

```bash
# The page: 401 (or a redirect) means the route exists and is protected. 404 means it is not registered.
curl -s -o /dev/null -w "%{http_code}\n" "<nextcloud-url>/index.php/apps/minimal_php_app/"

# The API route, authenticated:
curl -s -u <user>:<pass> "<nextcloud-url>/index.php/apps/minimal_php_app/api/whoami"

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

**The migration** is a class under `lib/Migration/` named `Version<version>Date<YmdHis>`, where `<version>`
is the app version without dots. Nextcloud runs pending migrations when the **installed app version
changes**, so bump `<version>` in `info.xml` and then:

```bash
occ app:disable <appid> && occ app:enable <appid>
```

Guard the schema change with `hasTable()` so re-running the step is harmless, and add an index on every
column you filter by.

**The entity** extends `OCP\AppFramework\Db\Entity`. Column `user_id` becomes property `$userId` with
generated `getUserId()`/`setUserId()`; declare those in `@method` annotations so tooling understands them,
and call `addType()` in the constructor so values come back as `int` rather than numeric strings.

**The mapper** extends `QBMapper` and builds queries with the query builder. Bind every value with
`createNamedParameter()`; never concatenate user input into SQL.

**In the controller**, inject the current user as `private ?string $userId` (lowercase). `$UserId` still
works but has been a deprecated alias since Nextcloud 26.

Verify:

```bash
# the table exists (adjust for your database)
occ db:convert-type --help >/dev/null && echo "use your DB client to check oc_<appid>_<table>"
# create and list through the API
curl -u <user>:<pass> -H 'OCS-APIRequest: true' -H 'Content-Type: application/json' \
    -X POST "<nextcloud-url>/index.php/apps/<appid>/api/items" -d '{"title":"first item"}'
curl -u <user>:<pass> -H 'OCS-APIRequest: true' "<nextcloud-url>/index.php/apps/<appid>/api/items"
```

Expected: `201` with the created row, then a list containing it. A `400` for an empty title proves the
controller's validation runs.

If it fails:

- **Table missing**: the app version was not bumped, so no migration ran. Check `occ app:list` shows the new
  version.
- **`Class not found`**: the migration's namespace must match `OCA\<Namespace>\Migration`.
- **Column mapping surprises**: entity properties are camelCase of the snake_case column; a property with no
  matching column is silently ignored on write.

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
