<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\MinimalPhpApp\Settings;

use OCA\MinimalPhpApp\AppInfo\Application;
use OCP\AppFramework\Http\TemplateResponse;
use OCP\AppFramework\Services\IInitialState;
use OCP\IAppConfig;
use OCP\Settings\ISettings;
use OCP\Util;

/**
 * The form rendered inside the section. Values reach the frontend through
 * IInitialState rather than being printed into the template, which keeps the data
 * out of the HTML and available to JavaScript as parsed JSON. Saving goes through
 * SettingsController::update(), an admin-only PUT route.
 */
class AdminSettings implements ISettings {
	public const CONFIG_KEY = 'greeting';

	public function __construct(
		private IAppConfig $appConfig,
		private IInitialState $initialState,
	) {
	}

	public function getForm(): TemplateResponse {
		// The value travels as initial state, the form's script reads it with loadState()
		// and saves through SettingsController. Same script naming as the page:
		// js/<appid>-admin.mjs after a build, js/<appid>-admin.js before.
		$this->initialState->provideInitialState(
			self::CONFIG_KEY,
			$this->appConfig->getValueString(Application::APP_ID, self::CONFIG_KEY, 'Hello'),
		);
		Util::addScript(Application::APP_ID, Application::APP_ID . '-admin');
		Util::addStyle(Application::APP_ID, Application::APP_ID . '-admin');

		return new TemplateResponse(Application::APP_ID, 'admin');
	}

	public function getSection(): string {
		return Application::APP_ID;
	}

	public function getPriority(): int {
		return 50;
	}
}
