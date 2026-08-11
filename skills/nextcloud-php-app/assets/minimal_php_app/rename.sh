#!/bin/sh
# SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Turn a copy of minimal_php_app into your own app.
#
# Renaming this app by hand is the single most error-prone step in the whole skill:
# the identifiers live in file contents, in file NAMES, and in a PHP class name that
# shares neither the app id nor the namespace. Missing any one of them produces an app
# that either fatals on `occ app:enable` or installs under the reference app's name.
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

case "$APP_ID" in
    *[!a-z0-9_]*) echo "app id must be lowercase letters, digits and underscores: $APP_ID" >&2; exit 2 ;;
esac

if [ ! -f appinfo/info.xml ] || [ ! -d lib/AppInfo ]; then
    echo "run this from inside your copy of minimal_php_app" >&2
    exit 2
fi

if [ "$APP_ID" = "minimal_php_app" ]; then
    echo "pick a different app id than the reference app" >&2
    exit 2
fi

# Table and index identifiers are capped at 30 characters including the oc_ prefix,
# so derive a short prefix for them rather than using the app id blindly.
SHORT=$(printf '%s' "$APP_ID" | cut -c1-12)
STAMP=$(date -u +%Y%m%d%H%M%S)
OLD_MIGRATION=Version1100Date20260811120000

replace() {  # replace <from> <to> ; portable across GNU and BSD sed
    from=$1
    to=$2
    files=$(grep -rIl "$from" . --exclude-dir=node_modules --exclude-dir=.git 2>/dev/null || true)
    [ -n "$files" ] || return 0
    printf '%s\n' "$files" | while IFS= read -r file; do
        sed -i.renamebak "s|${from}|${to}|g" "$file"
        rm -f "${file}.renamebak"
    done
}

echo "==> removing build artefacts and the reference README"
rm -rf node_modules test-results playwright-report
rm -f README.md rename.sh.renamebak

echo "==> renaming identifiers"
replace 'minimal_php_app_items' "${SHORT}_items"      # table name, before the app id itself
replace 'minimal_php_app_items_uid' "${SHORT}_items_uid"
replace 'minimal_php_app' "$APP_ID"
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

echo "==> resetting the manifest for a new app"
replace '<version>1.1.0</version>' '<version>1.0.0</version>'
replace 'Reference app for the nextcloud-php-app skill. It is the smallest app that still' "$DISPLAY_NAME."
replace 'shows every moving part: an app id, a bootstrap class, a navigation entry, a page rendered from a template,' 'TODO: describe your app.'
replace 'and a JSON API route. Copy it and grow it.' ''
replace '<author>Nextcloud AppAPI maintainers</author>' '<author>TODO your name</author>'
replace '<bugs>https://github.com/oleksandr-nc/nextcloud-skills/issues</bugs>' '<bugs>TODO your issue tracker</bugs>'
replace 'Minimal Nextcloud PHP app used by the nextcloud-php-app skill' "$DISPLAY_NAME"

echo "==> verifying that nothing of the reference app survived"
leaks=$(grep -rniE 'minimal|MinimalPhp|min_php|nextcloud-php-app|AppAPI maintainers' . \
    --exclude-dir=node_modules --exclude-dir=.git --exclude=rename.sh 2>/dev/null || true)
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
