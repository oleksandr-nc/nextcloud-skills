<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

require_once './vendor/autoload.php';

use Nextcloud\CodingStandard\Config;

// Nextcloud's shared php-cs-fixer rules; every app in the store uses this config.
$config = new Config();
$config
	->getFinder()
	->notPath('build')
	->notPath('node_modules')
	->notPath('vendor')
	->in(__DIR__);
return $config;
