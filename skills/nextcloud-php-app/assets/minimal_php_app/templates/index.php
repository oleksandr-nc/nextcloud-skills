<?php
/**
 * SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * Templates render inside Nextcloud's page frame. Escape everything you print with
 * p(); inline <script> is blocked by the Content Security Policy, so behaviour goes
 * into a file loaded with Util::addScript().
 */

\OCP\Util::addScript(\OCA\MinimalPhpApp\AppInfo\Application::APP_ID, 'main');
?>

<div id="minimal_php_app" class="app-minimal_php_app">
	<h2><?php p($l->t('Minimal PHP App')); ?></h2>
	<p><?php p($l->t('This page is rendered by a TemplateResponse.')); ?></p>
	<p id="whoami-output" data-testid="whoami-output"><?php p($l->t('Loading...')); ?></p>
</div>
