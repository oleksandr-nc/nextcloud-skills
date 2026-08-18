/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import { createAppConfig } from '@nextcloud/vite-config'

// One entry per page script. The output is js/<appid>-<entry>.mjs plus
// css/<appid>-<entry>.css (the app id is read from appinfo/info.xml), which is exactly
// what the template loads with Util::addScript() and Util::addStyle(). The build
// empties js/ and css/ first, so the plain-JavaScript files from the earlier stages
// are replaced by the built ones: there is no going back except through git.
export default createAppConfig({
	main: 'src/main.js',
}, {
	emptyOutputDirectory: {
		additionalDirectories: ['css'],
	},
})
