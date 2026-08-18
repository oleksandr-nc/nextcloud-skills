/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { createAppConfig } from '@nextcloud/vite-config'

// One entry per script Nextcloud loads: the page and the admin form. The output is
// js/<appid>-<entry>.mjs plus css/<appid>-<entry>.css (the app id is read from
// appinfo/info.xml), which is exactly what Util::addScript() and Util::addStyle() load.
// An entry's CSS file @imports the shared chunk CSS, so addStyle of the entry is enough.
// The build empties js/ and css/ first, so the plain-JavaScript files from the earlier
// stages are replaced by the built ones: there is no going back except through git.
export default createAppConfig({
	main: 'src/main.js',
	admin: 'src/admin.js',
}, {
	emptyOutputDirectory: {
		additionalDirectories: ['css'],
	},
})
