/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Plain JavaScript on purpose: no build step, no bundler. Util::addScript() looks for
 * js/minimal_php_app-main.mjs first and falls back to this file, so an app can start
 * without any frontend tooling and adopt Vue and Vite later (see src/ and
 * vite.config.js; the build replaces this file).
 *
 * OC.generateUrl and OC.requestToken are globals Nextcloud provides on every page.
 */

const APP_ID = 'minimal_php_app'

async function api(path, options = {}) {
	const response = await fetch(OC.generateUrl(`/apps/${APP_ID}${path}`), {
		...options,
		headers: { requesttoken: OC.requestToken, 'Content-Type': 'application/json', ...(options.headers ?? {}) },
	})
	if (!response.ok) {
		throw new Error(`HTTP ${response.status}`)
	}
	return response.json()
}

async function renderItems(list) {
	const items = await api('/api/items')
	list.replaceChildren(...items.map((item) => {
		const li = document.createElement('li')
		li.textContent = item.title
		return li
	}))
}

document.addEventListener('DOMContentLoaded', async () => {
	const output = document.getElementById('whoami-output')
	const form = document.getElementById('item-form')
	const input = document.getElementById('item-title')
	const list = document.getElementById('item-list')
	if (!output || !form) {
		return
	}

	try {
		const data = await api('/api/whoami')
		output.textContent = `Signed in as ${data.displayName} (${data.user})`
	} catch (error) {
		output.textContent = `Request failed: ${error.message}`
	}

	form.addEventListener('submit', async (event) => {
		event.preventDefault()
		if (input.value.trim() === '') {
			return
		}
		await api('/api/items', { method: 'POST', body: JSON.stringify({ title: input.value }) })
		input.value = ''
		await renderItems(list)
	})
	await renderItems(list)
})
