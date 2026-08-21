/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { defineConfig, devices } from '@playwright/test'

// Point the tests at an existing Nextcloud that has this app installed:
//   PLAYWRIGHT_BASE_URL=http://nextcloud.local npx playwright test
// The default matches the dev environment from the nextcloud-dev-setup skill.
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://nextcloud.local'

export default defineConfig({
	testDir: './playwright',
	fullyParallel: true,
	forbidOnly: !!process.env.CI,
	retries: process.env.CI ? 2 : 0,
	reporter: process.env.CI ? [['dot'], ['github']] : [['list']],
	use: {
		// Nextcloud serves its routes under /index.php/, so keeping it in the base URL
		// lets specs use relative paths like 'apps/minimal_php_app/'.
		baseURL: baseURL + '/index.php/',
		trace: 'on-first-retry',
		video: 'on-first-retry',
		ignoreHTTPSErrors: true,
	},
	projects: [
		{ name: 'chromium', use: { ...devices['Desktop Chrome'] } },
	],
})
