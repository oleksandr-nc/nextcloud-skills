<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->
<template>
	<div class="minimal-php-app">
		<h2>{{ t('minimal_php_app', 'Minimal PHP App') }}</h2>
		<p>{{ t('minimal_php_app', 'This page is rendered by a TemplateResponse.') }}</p>
		<p data-testid="whoami-output">{{ whoami }}</p>

		<form class="minimal-php-app__form" @submit.prevent="addItem">
			<NcTextField v-model="title"
				:label="t('minimal_php_app', 'New item')"
				data-testid="item-title-input" />
			<NcButton type="submit" variant="primary" data-testid="item-add-button">
				{{ t('minimal_php_app', 'Add') }}
			</NcButton>
		</form>

		<ul data-testid="item-list">
			<li v-for="item in items" :key="item.id">
				{{ item.title }}
			</li>
		</ul>
	</div>
</template>

<script setup>
import { onMounted, ref } from 'vue'
import axios from '@nextcloud/axios'
import { generateUrl } from '@nextcloud/router'
import { t } from '@nextcloud/l10n'
import NcButton from '@nextcloud/vue/components/NcButton'
import NcTextField from '@nextcloud/vue/components/NcTextField'

// @nextcloud/axios sends the CSRF token on every request, so the app's routes keep
// their protection and nothing here needs to know about tokens.
const whoami = ref(t('minimal_php_app', 'Loading...'))
const items = ref([])
const title = ref('')

async function loadItems() {
	const response = await axios.get(generateUrl('/apps/minimal_php_app/api/items'))
	items.value = response.data
}

async function addItem() {
	if (title.value.trim() === '') {
		return
	}
	await axios.post(generateUrl('/apps/minimal_php_app/api/items'), { title: title.value })
	title.value = ''
	await loadItems()
}

onMounted(async () => {
	try {
		const response = await axios.get(generateUrl('/apps/minimal_php_app/api/whoami'))
		whoami.value = `Signed in as ${response.data.displayName} (${response.data.user})`
	} catch (error) {
		whoami.value = `Request failed: ${error.message}`
	}
	await loadItems()
})
</script>

<style scoped>
.minimal-php-app {
	padding: 0 20px;
}

.minimal-php-app__form {
	display: flex;
	gap: 8px;
	align-items: flex-end;
	max-width: 400px;
	margin-bottom: 12px;
}

.minimal-php-app__form button {
	flex-shrink: 0;
}
</style>
