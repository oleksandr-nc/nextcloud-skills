<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\MinimalPhpApp\Db;

use OCP\AppFramework\Db\Entity;

/**
 * One row of minimal_php_app_items.
 *
 * Entity maps snake_case columns to camelCase properties: user_id becomes $userId,
 * and the generated accessors are getUserId()/setUserId(). Declaring them in the
 * @method annotations is what makes static analysis and IDEs understand the class.
 *
 * @method string getUserId()
 * @method void setUserId(string $userId)
 * @method string getTitle()
 * @method void setTitle(string $title)
 * @method int getCreatedAt()
 * @method void setCreatedAt(int $createdAt)
 */
class Item extends Entity implements \JsonSerializable {
	protected string $userId = '';
	protected string $title = '';
	protected int $createdAt = 0;

	public function __construct() {
		// Declaring types makes the mapper cast values coming from the database,
		// so getCreatedAt() returns an int rather than a numeric string.
		$this->addType('userId', 'string');
		$this->addType('title', 'string');
		$this->addType('createdAt', 'integer');
	}

	public function jsonSerialize(): array {
		return [
			'id' => $this->getId(),
			'title' => $this->getTitle(),
			'createdAt' => $this->getCreatedAt(),
		];
	}
}
