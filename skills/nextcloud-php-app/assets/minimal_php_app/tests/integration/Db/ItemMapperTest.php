<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\MinimalPhpApp\Tests\Integration\Db;

use OCA\MinimalPhpApp\Db\Item;
use OCA\MinimalPhpApp\Db\ItemMapper;
use OCP\Server;
use PHPUnit\Framework\Attributes\Group;
use Test\TestCase;

/**
 * An integration test: it talks to the instance's real database through the real
 * mapper, which is the only way to prove the migration, the entity and the queries
 * agree. \Test\TestCase comes from the Nextcloud server checkout, so this suite runs
 * inside one (see tests/bootstrap.php). Rows are cleaned up so the test can rerun.
 */
#[Group('DB')]
class ItemMapperTest extends TestCase {
	private ItemMapper $mapper;
	/** @var Item[] */
	private array $created = [];

	protected function setUp(): void {
		parent::setUp();
		$this->mapper = Server::get(ItemMapper::class);
	}

	protected function tearDown(): void {
		foreach ($this->created as $item) {
			$this->mapper->delete($item);
		}
		parent::tearDown();
	}

	private function insert(string $userId, string $title): Item {
		$item = new Item();
		$item->setUserId($userId);
		$item->setTitle($title);
		$item->setCreatedAt(time());
		return $this->created[] = $this->mapper->insert($item);
	}

	public function testRoundTripKeepsTypesAndFiltersByUser(): void {
		$suffix = uniqid();
		$mine = $this->insert("test-user-$suffix", 'mine');
		$this->insert("other-user-$suffix", 'not mine');

		$found = $this->mapper->findAllForUser("test-user-$suffix");

		$this->assertCount(1, $found);
		$this->assertSame($mine->getId(), $found[0]->getId());
		$this->assertSame('mine', $found[0]->getTitle());
		// addType('createdAt', 'integer') is what turns the database string back into an int.
		$this->assertIsInt($found[0]->getCreatedAt());
	}
}
