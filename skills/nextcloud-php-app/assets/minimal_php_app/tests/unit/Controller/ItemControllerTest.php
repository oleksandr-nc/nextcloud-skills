<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\MinimalPhpApp\Tests\Unit\Controller;

use OCA\MinimalPhpApp\Controller\ItemController;
use OCA\MinimalPhpApp\Db\Item;
use OCA\MinimalPhpApp\Db\ItemMapper;
use OCP\AppFramework\Http;
use OCP\IRequest;
use PHPUnit\Framework\MockObject\MockObject;
use PHPUnit\Framework\TestCase;

/**
 * A unit test: the controller is built by hand with a mocked mapper, so it runs
 * without a Nextcloud instance and without a database. This is the right level for
 * validation and response shapes; what the mapper does with the database is the
 * integration test's job.
 */
class ItemControllerTest extends TestCase {
	private ItemMapper&MockObject $mapper;
	private ItemController $controller;

	protected function setUp(): void {
		parent::setUp();
		$this->mapper = $this->createMock(ItemMapper::class);
		$this->controller = new ItemController(
			$this->createMock(IRequest::class),
			$this->mapper,
			'alice',
		);
	}

	public function testCreateRejectsAnEmptyTitle(): void {
		$this->mapper->expects($this->never())->method('insert');

		$response = $this->controller->create('   ');

		$this->assertSame(Http::STATUS_BAD_REQUEST, $response->getStatus());
		$this->assertSame(['error' => 'title is required'], $response->getData());
	}

	public function testCreateStoresTheItemForTheCurrentUser(): void {
		$this->mapper->expects($this->once())
			->method('insert')
			->with($this->callback(function (Item $item): bool {
				return $item->getUserId() === 'alice'
					&& $item->getTitle() === 'first item'
					&& $item->getCreatedAt() > 0;
			}))
			->willReturnArgument(0);

		$response = $this->controller->create('  first item ');

		$this->assertSame(Http::STATUS_CREATED, $response->getStatus());
		$this->assertSame('first item', $response->getData()->getTitle());
	}

	public function testIndexListsOnlyTheCurrentUsersItems(): void {
		$item = new Item();
		$item->setTitle('mine');
		$this->mapper->expects($this->once())
			->method('findAllForUser')
			->with('alice')
			->willReturn([$item]);

		$response = $this->controller->index();

		$this->assertSame(Http::STATUS_OK, $response->getStatus());
		$this->assertSame([$item], $response->getData());
	}
}
