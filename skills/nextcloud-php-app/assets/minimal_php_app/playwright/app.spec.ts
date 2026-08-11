/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * UI tests for the minimal app. They drive a real browser against a real Nextcloud,
 * which is the only way to catch what unit tests cannot: CSP violations, a script that
 * never loads, a route that redirects to the login page, a broken navigation entry.
 */

import { expect, test } from '@playwright/test'

const USER = process.env.NEXTCLOUD_USER ?? 'admin'
const PASSWORD = process.env.NEXTCLOUD_PASSWORD ?? 'admin'

/**
 * Log in through the real login form once per test file and keep the session in the
 * browser context. Prefer this over faking cookies: it exercises the same path a user
 * takes, and it breaks loudly when login itself regresses.
 */
test.beforeEach(async ({ page }) => {
	await page.goto('login')
	await page.locator('#user').fill(USER)
	await page.locator('#password').fill(PASSWORD)
	await page.locator('button[type="submit"]').click()
	await page.waitForURL(/apps|dashboard|files/)
})

test('the app page renders its template', async ({ page }) => {
	await page.goto('apps/minimal_php_app/')

	await expect(page.getByRole('heading', { name: 'Minimal PHP App' })).toBeVisible()
	await expect(page.getByText('This page is rendered by a TemplateResponse.')).toBeVisible()
})

test('the page script calls the API and renders the result', async ({ page }) => {
	await page.goto('apps/minimal_php_app/')

	// The placeholder is replaced only if js/main.js loaded, the CSP allowed it, and
	// the API answered. Asserting the final text covers all three at once.
	await expect(page.getByTestId('whoami-output')).toHaveText(`Signed in as ${USER} (${USER})`)
})

test('the app appears in the navigation', async ({ page }) => {
	await page.goto('apps/dashboard/')

	// The app menu is a popover: its entries are not in the DOM until it is opened,
	// so a plain link query on the loaded page finds nothing even when the entry is
	// registered correctly. Open it first, the way a user would.
	// exact: true matters here. The header carries two buttons whose accessible name
	// starts with "Open apps menu" (the waffle and the current-app one), and a loose
	// match resolves to both, which Playwright rejects under strict mode.
	await page.getByRole('button', { name: 'Open apps menu', exact: true }).click()

	// The entries are anchors, but Nextcloud gives them role="menuitem", so querying
	// for a link finds nothing. Always check the rendered role instead of assuming
	// that <a> means link.
	await expect(page.getByRole('menuitem', { name: 'Minimal PHP App' })).toBeVisible()
})

test('the app produces no errors of its own', async ({ page }) => {
	const errors: string[] = []

	// Uncaught exceptions from any script on the page are ours to care about.
	page.on('pageerror', (error) => errors.push(`uncaught: ${error.message}`))
	// For HTTP failures, filter to this app: a shared instance may have unrelated
	// apps failing, and an unfiltered assertion turns their bugs into your flaky test.
	page.on('response', (response) => {
		if (response.status() >= 400 && response.url().includes('minimal_php_app')) {
			errors.push(`${response.status()} ${response.url()}`)
		}
	})

	await page.goto('apps/minimal_php_app/')
	await expect(page.getByTestId('whoami-output')).not.toHaveText('Loading...')

	expect(errors).toEqual([])
})

test('the admin settings section renders', async ({ page }) => {
	await page.goto('settings/admin/minimal_php_app')

	await expect(page.getByTestId('admin-section')).toBeVisible()
	await expect(page.getByText('Admin settings rendered by an ISettings implementation.')).toBeVisible()
})

test('the data API stores and returns an item', async ({ page }) => {
	// request.post() from the page context reuses the session cookie, and Playwright
	// sends the CSRF token that the browser already has.
	const title = `playwright ${Date.now()}`
	await page.goto('apps/minimal_php_app/')

	const created = await page.evaluate(async (t) => {
		const response = await fetch(OC.generateUrl('/apps/minimal_php_app/api/items'), {
			method: 'POST',
			headers: { 'Content-Type': 'application/json', requesttoken: OC.requestToken },
			body: JSON.stringify({ title: t }),
		})
		return { status: response.status, body: await response.json() }
	}, title)

	expect(created.status).toBe(201)
	expect(created.body.title).toBe(title)
})
