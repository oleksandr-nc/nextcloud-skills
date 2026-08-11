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

/**
 * The form rendered inside the section. Values reach the frontend through
 * IInitialState rather than being printed into the template, which keeps the data
 * out of the HTML and available to JavaScript as parsed JSON.
 */
class AdminSettings implements ISettings {
	public const CONFIG_KEY = 'greeting';

	public function __construct(
		private IAppConfig $appConfig,
		private IInitialState $initialState,
	) {
	}

	public function getForm(): TemplateResponse {
		$this->initialState->provideInitialState(
			self::CONFIG_KEY,
			$this->appConfig->getValueString(Application::APP_ID, self::CONFIG_KEY, 'Hello'),
		);

		return new TemplateResponse(Application::APP_ID, 'admin');
	}

	public function getSection(): string {
		return Application::APP_ID;
	}

	public function getPriority(): int {
		return 50;
	}
}
