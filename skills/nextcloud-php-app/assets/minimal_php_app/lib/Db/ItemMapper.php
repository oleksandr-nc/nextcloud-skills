<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\MinimalPhpApp\Db;

use OCP\AppFramework\Db\QBMapper;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IDBConnection;

/**
 * Data access for Item. QBMapper gives insert/update/delete and the find* helpers;
 * queries are built with the query builder, never with string concatenation.
 *
 * @template-extends QBMapper<Item>
 */
class ItemMapper extends QBMapper {
	public function __construct(IDBConnection $db) {
		parent::__construct($db, 'minimal_php_app_items', Item::class);
	}

	/**
	 * @return Item[]
	 */
	public function findAllForUser(string $userId, int $limit = 50): array {
		$qb = $this->db->getQueryBuilder();
		$qb->select('*')
			->from($this->getTableName())
			// Always bind parameters. createNamedParameter is what keeps user input
			// out of the SQL string.
			->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId, IQueryBuilder::PARAM_STR)))
			->orderBy('created_at', 'DESC')
			->setMaxResults($limit);

		return $this->findEntities($qb);
	}
}
