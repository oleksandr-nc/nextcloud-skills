<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\MinimalPhpApp\Controller;

use OCA\MinimalPhpApp\AppInfo\Application;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http\Attribute\FrontpageRoute;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\Attribute\NoCSRFRequired;
use OCP\AppFramework\Http\JSONResponse;
use OCP\AppFramework\Http\TemplateResponse;
use OCP\IRequest;
use OCP\IUserSession;

/**
 * Routes are declared as PHP attributes on the methods, which is the current idiom;
 * appinfo/routes.php still works and is what older apps use.
 *
 * Access is deny-by-default: without #[NoAdminRequired] a route is admin-only, and
 * every route requires a logged-in user unless it carries #[PublicPage].
 */
class PageController extends Controller {
	public function __construct(
		IRequest $request,
		private IUserSession $userSession,
	) {
		parent::__construct(Application::APP_ID, $request);
	}

	/**
	 * The app's page. #[NoCSRFRequired] is needed because the browser navigates here
	 * directly, without a token; never put it on a state-changing route.
	 */
	#[NoAdminRequired]
	#[NoCSRFRequired]
	#[FrontpageRoute(verb: 'GET', url: '/')]
	public function index(): TemplateResponse {
		return new TemplateResponse(Application::APP_ID, 'index');
	}

	/**
	 * A JSON route the page calls. Same-origin requests from the page carry the CSRF
	 * token automatically, so this one does not waive it.
	 */
	#[NoAdminRequired]
	#[FrontpageRoute(verb: 'GET', url: '/api/whoami')]
	public function whoami(): JSONResponse {
		$user = $this->userSession->getUser();
		return new JSONResponse([
			'user' => $user?->getUID(),
			'displayName' => $user?->getDisplayName(),
		]);
	}
}
