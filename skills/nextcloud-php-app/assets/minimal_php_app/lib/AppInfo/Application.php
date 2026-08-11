<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\MinimalPhpApp\AppInfo;

use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;

/**
 * The app's entry point. Nextcloud instantiates this class for every request that
 * touches the app, so keep it cheap: register things here, do not do work here.
 */
class Application extends App implements IBootstrap {
	public const APP_ID = 'minimal_php_app';

	public function __construct(array $urlParams = []) {
		parent::__construct(self::APP_ID, $urlParams);
	}

	/**
	 * Register services, listeners, middlewares. Runs on every request; must not
	 * query the database or use \OC::$server.
	 */
	public function register(IRegistrationContext $context): void {
	}

	/**
	 * Runs after registration, when the DI container is ready. Use it for work that
	 * needs services; still keep it light.
	 */
	public function boot(IBootContext $context): void {
	}
}
