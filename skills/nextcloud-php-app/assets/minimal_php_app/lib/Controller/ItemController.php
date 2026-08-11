<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\MinimalPhpApp\Controller;

use OCA\MinimalPhpApp\AppInfo\Application;
use OCA\MinimalPhpApp\Db\Item;
use OCA\MinimalPhpApp\Db\ItemMapper;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http;
use OCP\AppFramework\Http\Attribute\FrontpageRoute;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\JSONResponse;
use OCP\IRequest;

/**
 * The app's data API. Kept apart from PageController because pages and JSON have
 * different concerns; both are wired by the same dependency injection.
 */
class ItemController extends Controller {
	public function __construct(
		IRequest $request,
		private ItemMapper $mapper,
		private ?string $userId,
	) {
		parent::__construct(Application::APP_ID, $request);
	}

	#[NoAdminRequired]
	#[FrontpageRoute(verb: 'GET', url: '/api/items')]
	public function index(): JSONResponse {
		return new JSONResponse($this->mapper->findAllForUser((string)$this->userId));
	}

	/**
	 * Method parameters are filled from the request body, so $title arrives from the
	 * posted JSON. State-changing routes keep CSRF protection: do not add
	 * #[NoCSRFRequired] here.
	 */
	#[NoAdminRequired]
	#[FrontpageRoute(verb: 'POST', url: '/api/items')]
	public function create(string $title = ''): JSONResponse {
		$title = trim($title);
		if ($title === '') {
			return new JSONResponse(['error' => 'title is required'], Http::STATUS_BAD_REQUEST);
		}

		$item = new Item();
		$item->setUserId((string)$this->userId);
		$item->setTitle($title);
		$item->setCreatedAt(time());

		return new JSONResponse($this->mapper->insert($item), Http::STATUS_CREATED);
	}
}
