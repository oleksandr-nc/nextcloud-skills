<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\MinimalPhpApp\Tests\Unit\Controller;

use OCA\MinimalPhpApp\Controller\SettingsController;
use OCP\AppFramework\Http;
use OCP\IAppConfig;
use OCP\IRequest;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;

class SettingsControllerTest extends TestCase {
	private IAppConfig&MockObject $appConfig;
	private SettingsController $controller;

	protected function setUp(): void {
		parent::setUp();
		$this->appConfig = $this->createMock(IAppConfig::class);
		$this->controller = new SettingsController($this->createMock(IRequest::class), $this->appConfig);
	}

	public function testUpdateStoresATrimmedGreeting(): void {
		$this->appConfig->expects($this->once())
			->method('setValueString')
			->with('minimal_php_app', 'greeting', 'Hi there');

		$response = $this->controller->update('  Hi there ');

		$this->assertSame(Http::STATUS_OK, $response->getStatus());
		$this->assertSame(['greeting' => 'Hi there'], $response->getData());
	}

	public function testUpdateRejectsAnEmptyGreeting(): void {
		$this->appConfig->expects($this->never())->method('setValueString');

		$this->assertSame(Http::STATUS_BAD_REQUEST, $this->controller->update('')->getStatus());
	}
}
