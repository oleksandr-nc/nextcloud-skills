/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { createApp } from 'vue'
import App from './App.vue'

// The template renders <div id="minimal_php_app">; the Vue app takes it over.
createApp(App).mount('#minimal_php_app')
