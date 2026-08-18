/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { createApp } from 'vue'
import AdminSettings from './AdminSettings.vue'

// A second Vite entry (see vite.config.js): js/<appid>-admin.mjs, loaded by
// AdminSettings::getForm(). It takes over the form inside the server-rendered section.
createApp(AdminSettings).mount('#minimal_php_app_admin_root')
