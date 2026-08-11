#!/bin/sh
# SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Read-only state collector for the Nextcloud AI stack. Changes nothing.
# Answers, in order: is there a provider at all, is it still initializing,
# is the queue moving, and is anything failing.
#
# Usage:
#   OCC="docker exec -u www-data nextcloud php occ" \
#   NC_URL=https://cloud.example.com NC_ADMIN=admin NC_ADMIN_PASS=... ./ai-doctor.sh
#
# Environment:
#   OCC            how to run occ            (default: occ)
#   NC_URL         Nextcloud base URL        (optional; enables the task-type check)
#   NC_ADMIN       admin user                (optional; needed with NC_URL)
#   NC_ADMIN_PASS  admin password or app password (optional; needed with NC_URL)

set -u

OCC=${OCC:-occ}
NC_URL=${NC_URL:-}
NC_ADMIN=${NC_ADMIN:-}
NC_ADMIN_PASS=${NC_ADMIN_PASS:-}

section() { printf '\n=== %s ===\n' "$1"; }
occ() { $OCC "$@" 2>/dev/null | grep -v 'Profiler output available'; }

section "Frontends and API integrations"
occ app:list | grep -E '^\s+- (assistant|integration_|context_chat|recognize)' || echo "  (none installed)"

section "Provider ExApps"
occ app_api:app:list || echo "  (AppAPI not installed or no ExApps)"
echo "-- containers --"
if [ -n "$(docker ps -aq --filter name=nc_app_ 2>/dev/null)" ]; then
    docker ps -a --filter name=nc_app_ --format '  {{.Names}}\t{{.Status}}' 2>/dev/null
else
    echo "  (no ExApp containers; local providers are not running here)"
fi

section "Initialization in flight (models still downloading)"
busy=0
for c in $(docker ps --filter name=nc_app_ --format '{{.Names}}' 2>/dev/null); do
    appid=${c#nc_app_}
    # .tmp is a download in progress, .lock is one that is starting or being finalised.
    tmp=$(docker exec "$c" sh -c \
        "ls -lh /nc_app_${appid}_data/*.tmp /nc_app_${appid}_data/*.lock 2>/dev/null | awk '{print \$5, \$9}'" \
        2>/dev/null)
    if [ -n "$tmp" ]; then
        busy=1
        echo "  $c is still fetching models:"
        printf '%s\n' "$tmp" | sed 's/^/    /'
    fi
done
[ "$busy" = 0 ] && echo "  (no in-flight downloads found; an app can still be initializing without .tmp files)"

section "Task types that currently have a provider"
if [ -n "$NC_URL" ] && [ -n "$NC_ADMIN" ] && [ -n "$NC_ADMIN_PASS" ]; then
    curl -s -u "$NC_ADMIN:$NC_ADMIN_PASS" -H 'OCS-APIRequest: true' \
        "$NC_URL/ocs/v2.php/taskprocessing/tasktypes?format=json" \
    | python3 -c "
import sys, json
try:
    types = json.load(sys.stdin)['ocs']['data']['types']
except Exception:
    print('  could not parse the response (wrong credentials or URL?)'); raise SystemExit
if not types:
    print('  NONE. No provider has registered; every AI feature is inert.'); raise SystemExit
for key in sorted(types):
    print('  ' + key)
" 2>/dev/null || echo "  (request failed)"
else
    echo "  skipped: set NC_URL, NC_ADMIN and NC_ADMIN_PASS to run the single most useful check"
fi

section "Task queue"
occ taskprocessing:task:stats || echo "  (taskprocessing commands unavailable)"

section "Background jobs (Task Processing depends on them)"
last=$(occ config:app:get core lastcron | tr -d '[:space:]')
if [ -n "$last" ] && [ "$last" -gt 0 ] 2>/dev/null; then
    now=$(date +%s)
    echo "  last cron run: $((now - last))s ago"
    [ $((now - last)) -gt 900 ] && echo "  WARNING: over 15 minutes ago; tasks will sit in 'scheduled'"
else
    echo "  could not read core.lastcron"
fi

section "Recently failed or stuck tasks"
occ taskprocessing:task:list --output=json \
    | python3 -c "
import sys, json
from collections import Counter
raw = sys.stdin.read().strip()
if not raw:
    print('  (no tasks)'); raise SystemExit
try:
    tasks = json.loads(raw)
except Exception:
    print('  (could not parse task list)'); raise SystemExit
tasks = tasks if isinstance(tasks, list) else tasks.get('tasks', [])
counts = Counter(str(t.get('status')) for t in tasks)
print('  by status: ' + (', '.join(f'{k}={v}' for k, v in counts.items()) or 'none'))
for t in tasks:
    if str(t.get('status')).lower().endswith(('failed', '4')) or t.get('errorMessage'):
        print(f\"  task {t.get('id')} type={t.get('type')} error={str(t.get('errorMessage'))[:100]}\")
" 2>/dev/null || echo "  (could not list tasks)"

section "Model storage"
docker system df -v 2>/dev/null | grep -E 'nc_app_.*_data' | awk '{print "  " $1 "\t" $NF}' \
    || echo "  (docker not available here)"

printf '\nDone. Nothing above was modified.\n'
