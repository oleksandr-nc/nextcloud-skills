#!/bin/sh
# SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Turn a copy of minimal_php_app into your own app.
#
# Renaming this app by hand is the single most error-prone step in the whole skill:
# the identifiers live in file contents, in file NAMES, and in a PHP class name that
# shares neither the app id nor the namespace. Missing any one of them produces an app
# that fails on `occ app:enable` (a missed namespace line: "Cannot declare class ...";
# a class name that no longer matches its file: "Migration step '...' is unknown") or
# installs under the reference app's name.
#
# Usage, from inside your copy:
#   sh rename.sh <app_id> <Namespace> "<Display Name>"
# Example:
#   sh rename.sh snippetbox SnippetBox "Snippet Box"
#
# Afterwards the directory contains no trace of the reference app, and the script
# verifies that itself before exiting.

set -eu

if [ $# -ne 3 ]; then
    echo "usage: sh rename.sh <app_id> <Namespace> \"<Display Name>\"" >&2
    echo "example: sh rename.sh snippetbox SnippetBox \"Snippet Box\"" >&2
    exit 2
fi

APP_ID=$1
NAMESPACE=$2
DISPLAY_NAME=$3

# Validate everything before touching a single file, so a rejected input leaves the
# copy exactly as it was.
case "$APP_ID" in
    *[!a-z0-9_]*) echo "app id must be lowercase letters, digits and underscores: $APP_ID" >&2; exit 2 ;;
esac
case "$NAMESPACE" in
    [A-Z]*) ;;
    *) echo "namespace must start with an uppercase letter: $NAMESPACE" >&2; exit 2 ;;
esac
case "$NAMESPACE" in
    *[!A-Za-z0-9]*) echo "namespace must be letters and digits only: $NAMESPACE" >&2; exit 2 ;;
esac
if [ -z "$DISPLAY_NAME" ]; then
    echo "display name must not be empty" >&2
    exit 2
fi

if [ ! -f appinfo/info.xml ] || [ ! -d lib/AppInfo ]; then
    echo "run this from inside your copy of minimal_php_app" >&2
    exit 2
fi

if [ "$APP_ID" = "minimal_php_app" ]; then
    echo "pick a different app id than the reference app" >&2
    exit 2
fi

# Table, column and index names are capped at 63 characters including the oc_ prefix
# (MigrationService::ensureNamingConstraints), which is what a long app id runs into.
if [ "$(printf 'oc_%s_items_uid' "$APP_ID" | wc -c)" -gt 63 ]; then
    echo "app id too long: oc_${APP_ID}_items_uid exceeds 63 characters" >&2
    exit 2
fi

STAMP=$(date -u +%Y%m%d%H%M%S)
OLD_MIGRATION=Version1100Date20260811120000

sed_escape() {  # make a string safe as the replacement part of s|from|to|
    printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

replace() {  # replace <from> <to> ; portable across GNU and BSD sed; never edits this script
    from=$1
    to=$(sed_escape "$2")
    files=$(grep -rIlF "$from" . --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git \
        --exclude=rename.sh 2>/dev/null || true)
    [ -n "$files" ] || return 0
    printf '%s\n' "$files" | while IFS= read -r file; do
        sed -i.renamebak "s|${from}|${to}|g" "$file"
        rm -f "${file}.renamebak"
    done
}

KEBAB=$(printf '%s' "$APP_ID" | tr '_' '-')

echo "==> removing build artefacts and the reference README"
rm -rf node_modules vendor build test-results playwright-report
rm -f README.md rename.sh.renamebak composer.lock

echo "==> renaming identifiers"
replace 'minimal_php_app' "$APP_ID"                    # also renames the table and index: <appid>_items, <appid>_items_uid
replace 'minimal-php-app' "$KEBAB"                     # CSS class names
replace 'MinimalPhpApp' "$NAMESPACE"

echo "==> renaming display strings"
replace 'Minimal PHP App' "$DISPLAY_NAME"
replace 'Minimal Nextcloud PHP app: one page, one API route' "$DISPLAY_NAME"
replace 'UI tests for the minimal app' "UI tests for $DISPLAY_NAME"

echo "==> renaming files, and the class name inside the migration"
# The migration class name matches its filename and contains neither the app id nor
# the namespace, so no substitution above touches it. This is what makes a hand rename
# fatal at install time.
NEW_MIGRATION="Version1000Date${STAMP}"
mv "lib/Migration/${OLD_MIGRATION}.php" "lib/Migration/${NEW_MIGRATION}.php"
replace "$OLD_MIGRATION" "$NEW_MIGRATION"
[ -f playwright/app.spec.ts ] && mv playwright/app.spec.ts "playwright/${APP_ID}.spec.ts"
# The page assets are named after the app id too (Util::addScript(APP_ID, APP_ID . '-main')).
for f in js/minimal_php_app-main.js js/minimal_php_app-admin.js css/minimal_php_app-main.css css/minimal_php_app-admin.css; do
    [ -f "$f" ] && mv "$f" "$(printf '%s' "$f" | sed "s|minimal_php_app|${APP_ID}|")"
done

echo "==> resetting the manifest for a new app"
replace '<version>1.1.0</version>' '<version>1.0.0</version>'
replace '"version": "1.1.0"' '"version": "1.0.0"'
replace 'Reference app for the nextcloud-php-app skill. It is the smallest app that still' "$DISPLAY_NAME."
replace 'shows every moving part: an app id, a bootstrap class, a navigation entry, a page rendered from a template,' 'TODO: describe your app.'
replace 'and a JSON API route. Copy it and grow it.' ''
replace '<author>Nextcloud AppAPI maintainers</author>' '<author>TODO your name</author>'
replace '<bugs>https://github.com/oleksandr-nc/nextcloud-skills/issues</bugs>' '<bugs>TODO your issue tracker</bugs>'
replace 'Minimal Nextcloud PHP app used by the nextcloud-php-app skill' "$DISPLAY_NAME"

echo "==> verifying that nothing of the reference app survived"
leaks=$(grep -rnE 'minimal_php_app|MinimalPhpApp|minimal-php-app|Minimal PHP App|nextcloud-php-app|AppAPI maintainers' . \
    --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git \
    --exclude=rename.sh --exclude=package-lock.json 2>/dev/null || true)
if [ -n "$leaks" ]; then
    echo "FAIL: reference-app strings remain:" >&2
    printf '%s\n' "$leaks" >&2
    exit 1
fi

# The class inside every migration must equal its filename, or PHP fatals on install.
for f in lib/Migration/Version*.php; do
    base=$(basename "$f" .php)
    grep -q "class ${base} " "$f" || {
        echo "FAIL: $f does not declare class $base" >&2
        exit 1
    }
done

rm -f rename.sh
echo
echo "Done. $APP_ID ($DISPLAY_NAME), namespace OCA\\${NAMESPACE}."
echo "Remaining TODOs: <description>, <author> and <bugs> in appinfo/info.xml."
echo "Next: occ app:enable $APP_ID"
