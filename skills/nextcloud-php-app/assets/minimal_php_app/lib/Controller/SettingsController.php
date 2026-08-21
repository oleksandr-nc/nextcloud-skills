<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\MinimalPhpApp\Controller;

use OCA\MinimalPhpApp\AppInfo\Application;
use OCA\MinimalPhpApp\Settings\AdminSettings;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http;
use OCP\AppFramework\Http\Attribute\FrontpageRoute;
use OCP\AppFramework\Http\JSONResponse;
use OCP\IAppConfig;
use OCP\IRequest;

/**
 * Writes the value the admin settings form shows. Deliberately WITHOUT
 * #[NoAdminRequired]: the deny-by-default model makes this route admin-only, and there
 * is nothing else to do for that. Reading the value happens through IInitialState in
 * AdminSettings::getForm(), so no GET route is needed.
 */
class SettingsController extends Controller {
	public function __construct(
		IRequest $request,
		private IAppConfig $appConfig,
	) {
		parent::__construct(Application::APP_ID, $request);
	}

	#[FrontpageRoute(verb: 'PUT', url: '/api/settings')]
	public function update(string $greeting = ''): JSONResponse {
		$greeting = trim($greeting);
		if ($greeting === '' || mb_strlen($greeting) > 100) {
			return new JSONResponse(['error' => 'greeting must be 1 to 100 characters'], Http::STATUS_BAD_REQUEST);
		}
		// IAppConfig also offers get/setValueInt, ...Bool, ...Array; use the typed one for the value.
		$this->appConfig->setValueString(Application::APP_ID, AdminSettings::CONFIG_KEY, $greeting);
		return new JSONResponse(['greeting' => $greeting]);
	}
}
