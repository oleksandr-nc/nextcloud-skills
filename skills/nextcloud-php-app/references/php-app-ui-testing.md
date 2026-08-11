<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Verifying a PHP app in the browser with Playwright

A detailed runbook, part of the [nextcloud-php-app](../SKILL.md) skill. Server-side checks prove a route
exists; only a browser proves the page works. Every locator and every trap below was executed against a
running Nextcloud.

Playwright is where Nextcloud is heading: the server ships `playwright.config.ts` next to its older Cypress
setup, and apps including activity, circles, text, twofactor_totp and viewer already use it.

Last verified against: Nextcloud master (35), Playwright 1.62.1, Node 22, on 2026-08-11 (6 tests, all
passing against a live instance).

## Setup

The reference app already contains all of this
([assets/minimal_php_app/](../assets/minimal_php_app/)); these are the pieces if you are adding them to an
existing app.

```jsonc
// package.json
"devDependencies": { "@playwright/test": "^1.62.1" },
"scripts": {
    "playwright": "playwright test",
    "playwright:ui": "playwright test --ui",
    "playwright:install": "playwright install chromium"
}
```

```ts
// playwright.config.ts
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://nextcloud.local'

export default defineConfig({
    testDir: './playwright',
    use: {
        baseURL: baseURL + '/index.php/',   // lets specs use 'apps/<appid>/'
        trace: 'on-first-retry',
        video: 'on-first-retry',
    },
    projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
})
```

```bash
npm install
npm run playwright:install          # downloads the browser, about 115 MB, once
PLAYWRIGHT_BASE_URL=<nextcloud-url> npm run playwright
```

Both installs are one-time. `node_modules/` is not tracked in this repository, so a fresh clone always needs
them; a copy taken from a checkout where the suite has already run may carry them along and start instantly.

`OC` is a global that Nextcloud injects into the page, and it has no TypeScript declaration. Playwright
transpiles specs without typechecking, so `OC.generateUrl(...)` runs fine either way, but add a declaration if
you run `tsc` over your tests:

```ts
declare const OC: { generateUrl: (path: string) => string, requestToken: string }
```

Keeping `/index.php/` in `baseURL` is what allows specs to navigate to `apps/<appid>/` instead of repeating
the prefix everywhere.

### Which Nextcloud to test against

Two options, and the `PLAYWRIGHT_BASE_URL` override is what makes both work from one config:

- **An existing development instance** (what the command above does). Fastest loop, and it is the same
  instance you are already looking at.
- **A container started by the test run**, using the official
  [`@nextcloud/e2e-test-server`](https://www.npmjs.com/package/@nextcloud/e2e-test-server) package in a
  `webServer` block, which is how the server and the activity app do it in CI. Note that helpers such as
  `createRandomUser()` reach into the managed container with `docker exec`, so they only work against a
  container the run itself started.

## Logging in

Nextcloud has no test-only login shortcut, so drive the real form. It is also the honest thing to do: it
breaks when login breaks.

```ts
test.beforeEach(async ({ page }) => {
    await page.goto('login')
    await page.locator('#user').fill(USER)
    await page.locator('#password').fill(PASSWORD)
    await page.locator('button[type="submit"]').click()
    await page.waitForURL(/apps|dashboard|files/)
})
```

For a large suite, do this once in a `setup` project and reuse the saved `storageState`, the way the server's
own suite does.

## The starter tests

Six of them, in [playwright/app.spec.ts](../assets/minimal_php_app/playwright/app.spec.ts); each covers a
failure the previous layer cannot see.

1. **The template renders**: asserts the heading and static text. Catches a controller returning the wrong
   template or a fatal error swallowed into an error page.
2. **The script ran and the API answered**: asserts the placeholder text has been replaced with the API's
   result. One assertion covers three things at once, because the text only changes if the script loaded, the
   CSP allowed it, and the route answered.
3. **The navigation entry is reachable**: opens the app menu and finds the entry.
4. **The app produces no errors of its own**: no uncaught exceptions, and no failing HTTP request belonging to
   this app.
5. **The admin settings section renders**: proves the `ISettings` and section registration in `info.xml`
   actually resolve, which nothing server-side tells you.
6. **The data API stores a row**: performs an authenticated `POST` from inside the page with
   `page.evaluate()`, so the browser's own session and CSRF token are used:

   ```ts
   const created = await page.evaluate(async (t) => {
       const response = await fetch(OC.generateUrl('/apps/<appid>/api/items'), {
           method: 'POST',
           headers: { 'Content-Type': 'application/json', requesttoken: OC.requestToken },
           body: JSON.stringify({ title: t }),
       })
       return { status: response.status, body: await response.json() }
   }, title)
   ```

   This is the browser-side counterpart of the `OCS-APIRequest` header that `curl` needs: inside the page you
   already have a session, so you send the CSRF token instead.

## Four traps that make a correct app look broken

Each of these cost a debugging round on a working app, so they are worth knowing before you write locators.

**The app menu is a popover.** Its entries are not in the DOM until it is opened. A query for the app's link
on a loaded page returns zero even when the entry is registered perfectly. Open the menu first.

**Its entries are not links.** They are anchors with `role="menuitem"`, so `getByRole('link', ...)` matches
nothing. Check the rendered role instead of assuming that `<a>` means link:

```ts
await page.getByRole('button', { name: 'Open apps menu', exact: true }).click()
await expect(page.getByRole('menuitem', { name: 'Minimal PHP App' })).toBeVisible()
```

**`exact: true` is not optional there.** The header carries two buttons whose accessible name begins with
"Open apps menu" (the waffle, and the current-app button), and Playwright's strict mode fails a locator that
resolves to two elements.

**Scope error assertions to your app.** A blanket "no console errors" assertion fails on a shared instance
because some other app is unhealthy: ours failed on a 500 from the notifications API that had nothing to do
with the app under test. Assert on uncaught exceptions plus failing requests whose URL belongs to your app:

```ts
page.on('pageerror', (error) => errors.push(`uncaught: ${error.message}`))
page.on('response', (response) => {
    if (response.status() >= 400 && response.url().includes('minimal_php_app')) {
        errors.push(`${response.status()} ${response.url()}`)
    }
})
```

## Debugging a failing test

```bash
npx playwright test --ui                       # timeline, DOM snapshots, live re-runs
npx playwright test --headed -g "navigation"   # watch it happen
npx playwright show-trace test-results/<test>/trace.zip
```

When a locator finds nothing, dump what is actually there rather than guessing. A throwaway spec that prints
every anchor, or the `outerHTML` of the element you expected, answers in one run what selector-tweaking does
not:

```ts
const el = page.locator('a[href*="<appid>"]').first()
console.log(await el.evaluate((e) => e.outerHTML))
```

That is exactly how the `role="menuitem"` surprise above was found.

## Related

- [php-app-development.md](php-app-development.md): the app these tests verify.
- [nextcloud-dev-setup](../../nextcloud-dev-setup/SKILL.md): the instance to test against.
- Playwright documentation: https://playwright.dev
