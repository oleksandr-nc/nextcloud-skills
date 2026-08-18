<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

// Two ways to run the tests, one bootstrap:
//
// 1. Inside a Nextcloud checkout (the app lives in apps/, apps-extra/ or custom_apps/):
//    the server's own test bootstrap boots Nextcloud, so tests can use the real
//    database and \Test\TestCase. This is how the "integration" suite runs.
// 2. Standalone, after `composer install`: only the OCP interfaces from nextcloud/ocp
//    are available, which is enough for the "unit" suite.
$serverBootstrap = __DIR__ . '/../../../tests/bootstrap.php';
if (file_exists($serverBootstrap)) {
	require_once $serverBootstrap;
	\OC_App::loadApp('minimal_php_app');
	\OC_Hook::clear();
} else {
	require_once __DIR__ . '/../vendor/autoload.php';
}
