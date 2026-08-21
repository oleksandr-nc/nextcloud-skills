/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * The admin form in plain JavaScript. OCP.InitialState.loadState() reads what
 * AdminSettings::getForm() provided; the save is a PUT to the app's admin-only route.
 * The Vue version of the same form is src/AdminSettings.vue.
 */

const APP_ID = 'minimal_php_app'

document.addEventListener('DOMContentLoaded', () => {
	const form = document.getElementById(`${APP_ID}_admin_form`)
	const input = document.getElementById(`${APP_ID}_greeting`)
	const status = document.getElementById(`${APP_ID}_admin_status`)
	if (!form) {
		return
	}

	input.value = OCP.InitialState.loadState(APP_ID, 'greeting')

	form.addEventListener('submit', async (event) => {
		event.preventDefault()
		const response = await fetch(OC.generateUrl(`/apps/${APP_ID}/api/settings`), {
			method: 'PUT',
			headers: { requesttoken: OC.requestToken, 'Content-Type': 'application/json' },
			body: JSON.stringify({ greeting: input.value }),
		})
		const data = await response.json()
		status.textContent = response.ok ? `Saved: ${data.greeting}` : `Error: ${data.error}`
	})
})
