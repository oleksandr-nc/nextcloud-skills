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

Last verified against: Nextcloud master (35), 34.0.2 and 33.0.7, Playwright 1.62.1, Node 22, on 2026-08-18
(7 tests, all passing against all three live instances, against the plain-JavaScript page and against the
Vue build).

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

## Two ways to use a browser, and you want both

Playwright drives a real browser, but **nobody looks at the page**: you write assertions and get pass or
fail. That is what you want for regression tests, and it is the wrong tool for finding out why a locator
matches nothing.

The complement is a browser the agent can drive interactively, through an MCP browser server such as
`chrome-devtools-mcp` ([set-up in the dev-setup skill](../../nextcloud-dev-setup/references/dev-environment.md#stage-8-optional-give-the-agent-a-browser)).
It returns the page's **accessibility tree**, which is the same information a locator needs:

```
menu "Apps"
  menuitem "Minimal PHP App"
```

That single snapshot answers the question that costs a debugging round otherwise: the app-menu entries are
`menuitem`, not `link`. Every trap in the section below was discovered the slow way and would have been
visible instantly here.

So the workflow is **explore live, then freeze**:

1. Drive the page with the browser tool: navigate, log in, click, snapshot.
2. Read the roles and accessible names from the snapshot.
3. Write the Playwright locator from what you saw, and keep it as a test.

Step 3 is what makes it durable. An interactive session ends; a spec keeps checking forever.

If your agent has no browser tool, the fallback is the throwaway spec at the end of this page that prints
`outerHTML`. It works, it is just slower.

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
    // dismiss the first-run wizard, see the traps below
    await page.evaluate(() => fetch(OC.generateUrl('/apps/firstrunwizard/wizard'), {
        method: 'DELETE',
        headers: { requesttoken: OC.requestToken },
    }))
})
```

For a large suite, do this once in a `setup` project and reuse the saved `storageState`, the way the server's
own suite does.

Tests that need a **second, non-admin user** (to prove that users only see their own data, or that a route
is admin-only) must create it, and a stock instance's password policy rejects short or common passwords
(`Password is among the 1,000,000 most common ones ... needs to be at least 10 characters long`). Create the
user with a policy-compliant password from the environment and pass the same value to the suite:

```bash
# in a container: docker exec -e OC_PASS='...' -u www-data <nextcloud-container> php occ user:add --password-from-env <uid>
OC_PASS='Playwright-Second-User-2026!' occ user:add --password-from-env <uid>
```

Do not assume a user exists on every instance; the reference suite reads `NEXTCLOUD_USER` and
`NEXTCLOUD_PASSWORD` for the same reason.

## The starter tests

Seven of them, in [playwright/app.spec.ts](../assets/minimal_php_app/playwright/app.spec.ts); each covers a
failure the previous layer cannot see.

1. **The template renders**: asserts the heading and static text. Catches a controller returning the wrong
   template or a fatal error swallowed into an error page.
2. **The script ran and the API answered**: asserts the placeholder text has been replaced with the API's
   result. One assertion covers three things at once, because the text only changes if the script loaded, the
   CSP allowed it, and the route answered.
3. **The navigation entry is reachable**: opens the app menu and finds the entry.
4. **The app produces no errors of its own**: no uncaught exceptions, and no failing HTTP request belonging to
   this app.
5. **The admin settings section renders and saves**: proves the `ISettings` and section registration in
   `info.xml` actually resolve, which nothing server-side tells you, then fills the field, saves, reloads and
   expects the stored value back (and restores the default, so the test leaves no trace).
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
7. **The page's own form works**: types a title into the field, clicks the button, and expects the list to
   show it. It locates by **accessible label and role** (`getByLabel('New item')`,
   `getByRole('button', { name: 'Add' })`), not by `data-testid` or DOM shape, and that is what lets the same
   test pass against the plain `<input aria-label>` and against the `NcTextField` component after the Vue
   build. Accessible names are the stable contract; a browser tool's snapshot shows you exactly which ones a
   page exposes.

## Traps that make a correct app look broken

Each of these cost a debugging round on a working app, so they are worth knowing before you write locators.

**The app menu is a popover on Nextcloud 34 and later.** Its entries are not in the DOM until it is opened. A
query for the app's link on a loaded page returns zero even when the entry is registered perfectly. Open the
menu first. On Nextcloud 33 there is nothing to open: the menu is rendered inline in the header, as
`navigation "Applications menu"` with plain links, and no "Open apps menu" button exists.

**The popover's entries are not links.** They are anchors with `role="menuitem"`, so `getByRole('link', ...)`
matches nothing on 34+ (on 33 they are links). Check the rendered role instead of assuming that `<a>` means
link. The reference test handles both versions:

```ts
const waffle = page.getByRole('button', { name: 'Open apps menu', exact: true })
if (await waffle.count() > 0) {          // 34+: popover; 33: inline navigation, no button
    await waffle.click()
}
const entry = page.getByRole('menuitem', { name: 'Minimal PHP App' })
    .or(page.getByRole('link', { name: 'Minimal PHP App' }))
await expect(entry).toBeVisible()
```

**`exact: true` is not optional there.** The header carries two buttons whose accessible name begins with
"Open apps menu" (the waffle, and the current-app button), and Playwright's strict mode fails a locator that
resolves to two elements.

**Some `@nextcloud/vue` inputs are not where their role is.** `NcCheckboxRadioSwitch` renders a visually
hidden `<input type="checkbox">` under a label span, so `getByRole('checkbox', ...).click()` resolves the right
element and then times out with `<span class="checkbox-content ..."> intercepts pointer events`. Click the
visible label text (`row.getByText('Read', { exact: true }).click()`) or use `check({ force: true })`, and
assert on the state with `toBeChecked()`. Text fields and buttons behave; toggles, checkboxes and radios are
the ones to watch.

**`fullyParallel: true` assumes state-free tests.** The reference config runs tests in parallel workers,
which is safe only because no reference test changes something another one reads. As soon as a test edits
shared state (an admin setting, the current user's list), either make it self-contained (unique data,
restore in `finally`), or run one worker (`workers: 1`, or `--workers 1`), or serialise the file with
`test.describe.configure({ mode: 'serial' })`. Serial mode also **skips the rest of the file after the first
failure** ("3 did not run"), which hides information while you are debugging; one worker does not.

**The first-run wizard swallows clicks.** On an instance where the user has never dismissed it, the
`firstrunwizard` app opens a modal on every page, and its overlay intercepts pointer events: Playwright reports
`<div role="dialog" ... id="firstrunwizard"> subtree intercepts pointer events` and the click times out, while
assertions that only read the page keep passing. Dismiss it the way its close button does, once per user, before
interacting: `DELETE /index.php/apps/firstrunwizard/wizard` from inside the page (in the login helper above;
harmless when the wizard is already gone or the app is disabled). The equivalent from the shell is
`occ user:setting <user> firstrunwizard show <nextcloud-version>`.

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
