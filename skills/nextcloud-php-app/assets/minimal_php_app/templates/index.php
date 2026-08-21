<?php
/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Templates render inside Nextcloud's page frame. Escape everything you print with
 * p(); inline <script> is blocked by the Content Security Policy, so behaviour goes
 * into a file loaded with Util::addScript().
 *
 * The asset name is "<appid>-main": Util::addScript() resolves js/<name>.mjs first
 * (the Vite build output) and falls back to js/<name>.js (the plain script), and
 * Util::addStyle() loads css/<name>.css. The same template serves both stages.
 */

use OCA\MinimalPhpApp\AppInfo\Application;

\OCP\Util::addScript(Application::APP_ID, Application::APP_ID . '-main');
\OCP\Util::addStyle(Application::APP_ID, Application::APP_ID . '-main');
?>

<!-- #app-content is the server's hook for the main panel background and scrolling. -->
<div id="app-content">
	<div id="minimal_php_app" class="minimal-php-app">
		<h2><?php p($l->t('Minimal PHP App')); ?></h2>
		<p><?php p($l->t('This page is rendered by a TemplateResponse.')); ?></p>
		<p id="whoami-output" data-testid="whoami-output"><?php p($l->t('Loading...')); ?></p>

		<form id="item-form" class="minimal-php-app__form">
			<input id="item-title" type="text" data-testid="item-title-input"
				placeholder="<?php p($l->t('New item')); ?>" aria-label="<?php p($l->t('New item')); ?>">
			<button type="submit" class="primary" data-testid="item-add-button"><?php p($l->t('Add')); ?></button>
		</form>
		<ul id="item-list" data-testid="item-list"></ul>
	</div>
</div>
