/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Plain JavaScript on purpose: no build step, no bundler. Util::addScript() looks for
 * js/main.mjs first and falls back to this js/main.js, so an app can start without any
 * frontend tooling and add Vite later.
 *
 * OC.generateUrl and OC.requestToken are globals Nextcloud provides on every page.
 */
document.addEventListener('DOMContentLoaded', async () => {
	const output = document.getElementById('whoami-output')
	if (!output) {
		return
	}

	try {
		const response = await fetch(OC.generateUrl('/apps/minimal_php_app/api/whoami'), {
			headers: { requesttoken: OC.requestToken },
		})
		if (!response.ok) {
			throw new Error(`HTTP ${response.status}`)
		}
		const data = await response.json()
		output.textContent = `Signed in as ${data.displayName} (${data.user})`
	} catch (error) {
		output.textContent = `Request failed: ${error.message}`
	}
})
