<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->
<template>
	<div>
		<form class="minimal-php-app__form" @submit.prevent="save">
			<NcTextField v-model="greeting" :label="t('minimal_php_app', 'Greeting')" maxlength="100" />
			<NcButton type="submit" variant="primary">
				{{ t('minimal_php_app', 'Save') }}
			</NcButton>
		</form>
		<p data-testid="admin-status" aria-live="polite">{{ status }}</p>
	</div>
</template>

<script setup>
import { ref } from 'vue'
import axios from '@nextcloud/axios'
import { loadState } from '@nextcloud/initial-state'
import { t } from '@nextcloud/l10n'
import { generateUrl } from '@nextcloud/router'
import NcButton from '@nextcloud/vue/components/NcButton'
import NcTextField from '@nextcloud/vue/components/NcTextField'

// loadState() reads what AdminSettings::getForm() provided through IInitialState:
// no extra GET route, and the value never appears in the HTML.
const greeting = ref(loadState('minimal_php_app', 'greeting'))
const status = ref('')

async function save() {
	try {
		const response = await axios.put(generateUrl('/apps/minimal_php_app/api/settings'), { greeting: greeting.value })
		status.value = `Saved: ${response.data.greeting}`
	} catch (error) {
		status.value = `Error: ${error.response?.data?.error ?? error.message}`
	}
}
</script>

<style scoped>
.minimal-php-app__form {
	display: flex;
	gap: 8px;
	align-items: center;
	max-width: 400px;
}

.minimal-php-app__form button {
	flex-shrink: 0;
}
</style>
