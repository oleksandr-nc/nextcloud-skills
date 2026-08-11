<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Diagnosing the AI stack

A detailed runbook, part of the [nextcloud-ai-stack](../SKILL.md) skill. Setting the stack up in the first
place is [ai-stack.md](ai-stack.md).

Last verified against: Nextcloud master (35), AppAPI 35.0.0-dev.1, HaRP 0.4.3, llm2 2.8.0, on 2026-08-11.

## Split the problem with one command

```bash
curl -s -u <admin>:<pass> -H 'OCS-APIRequest: true' \
    '<nextcloud-url>/ocs/v2.php/taskprocessing/tasktypes?format=json'
```

It lists **only task types that currently have a provider**. That single fact separates the two halves of
every AI support case. The list is cached for 60 seconds, so re-query once before trusting a short answer.

| Result | The problem is | Go to |
|---|---|---|
| The task type you need is **absent** | the provider layer: not installed, still initializing, init failed, or an integration without credentials | [No provider](#no-provider-for-the-task-type) |
| The task type is **present** but tasks never finish | the scheduling and execution layer | [Tasks do not complete](#tasks-do-not-complete) |
| Tasks finish, but users see nothing | the frontend layer: Assistant missing, task type disabled, or the feature lives elsewhere in the UI | [Frontend](#frontend-shows-nothing) |

## No provider for the task type

Work down this list; each step has a command that answers it definitively.

**1. Is the provider app installed and running?**

```bash
occ app_api:app:list                        # local providers (ExApps)
occ app:list | grep -E 'assistant|integration_'   # frontend and API integrations
docker ps --filter name=nc_app_             # containers actually running
```

**2. Is it still initializing?** This is the most common answer, and the most misleading, because
`app_api:app:list` prints `[enabled]` the whole time. A provider registers its task types in its `/enabled`
handler, which AppAPI calls only after init reports 100, so nothing is registered while models download.

```bash
docker logs -f nc_app_<appid>                          # what it is doing right now
docker exec nc_app_<appid> ls -l /nc_app_<appid>_data  # model files; a .tmp file means a download in flight
```

The AppAPI admin page shows the same progress as a percentage. Multi-GB model downloads take as long as your
link takes; nothing is wrong until the numbers stop moving.

**3. Did init fail?** A failed init leaves an error on the app and the providers never appear. The container
log holds the reason; typical causes are no network to the model host, a full disk, or the app crashing on
startup. A crashed task loop can be silent: the app answers heartbeats and looks healthy while its worker
thread is dead, so read the log from the beginning rather than the tail.

**4. Is it an external integration missing credentials?** Integrations register providers only once
configured. Check the app's section in **Administration settings > Artificial intelligence**.

**5. Is the task type disabled?** A disabled task type is not offered even with a healthy provider:

```bash
occ taskprocessing:task-type:set-enabled <task-type-id> 1
```

## Tasks do not complete

**Stuck in `scheduled`.** The task was accepted but never picked up. Two very different causes, and one
command tells them apart.

```bash
occ taskprocessing:task:get <id>       # confirm the status and read any error
occ taskprocessing:task:stats          # how many tasks sit in each state
occ background-job:list                # is the job queue moving at all
```

**Is the provider even asking for work?** A provider ExApp claims tasks itself, by calling
`GET /ocs/v2.php/taskprocessing/tasks_provider/next`. Count those requests and look at the container:

```bash
docker logs --since 20m <nextcloud-container> 2>&1 | grep -c tasks_provider/next
docker stats --no-stream <container>   # an idle provider with a pending task is the tell
```

Zero requests plus an idle container means the app's task loop is dead, no matter how healthy it looks
otherwise. **A crashed loop is silent**: the app still answers heartbeats, still registers all its providers,
and the task type is still listed, so every layer above looks correct. Read the container log **from the
beginning**:

```bash
docker logs <container> 2>&1 | grep -aiE 'traceback|error|exception' | head
```

Worked example, reproduced on 2026-08-11 with llm2 2.8.0: the CPU image builds `FROM ubuntu:22.04`, which
gives Python 3.10, while the code calls `asyncio.TaskGroup()`, added in Python 3.11. The startup log holds a
single `background_task_loop crashed` traceback, after which the app registered 52 providers and served
heartbeats normally while claiming no task for 20 minutes. The fix is upstream, in the image; the diagnosis
is one `grep` once you know to look at the beginning of the log.

Task Processing dispatches through background jobs, so a broken cron freezes every AI feature while leaving
the apps looking perfectly healthy. Confirm cron ran recently in **Administration settings > Basic settings**
before suspecting any AI component. For synchronous providers you can also run a dedicated worker:

```bash
occ taskprocessing:worker --taskTypes <task-type-id>
```

**Goes to `running`, then fails.** Now it is the provider's runtime. `occ taskprocessing:task:get <id>`
carries the error message; `docker logs nc_app_<appid>` carries the traceback. Two frequent causes:

- **Out of memory.** A container killed by the OOM killer exits with code 137
  (`docker inspect nc_app_<appid> --format '{{.State.ExitCode}}'`). Give the host more RAM, use a smaller or
  more quantised model, or move to GPU.
- **A model that was never fully downloaded**, for example after a failed init that was not retried.

**Everything works but is slow on CPU.** Expected. Local generation on CPU is memory-bandwidth bound. The
options are a GPU daemon, a smaller model, or an external API provider.

## Frontend shows nothing

- Assistant not installed or disabled: `occ app:list | grep assistant`.
- The capability exists but is exposed elsewhere: translation appears in Talk and Text, speech to text in
  Talk recordings, image generation in the Assistant only.
- The user's group lacks access to the app.

## Symptom table

| Symptom | Cause and fix |
|---|---|
| Assistant offers no actions at all | No task type has a provider. Start at the tasktypes endpoint above |
| `core:text2text` missing although llm2 is `[enabled]` | Init is still running (models downloading) or init failed. `[enabled]` is not readiness; check init progress and the container log |
| Task stays `scheduled` forever | Either background jobs and cron are not running, or the provider's task loop is dead and it never claims the task. Count `tasks_provider/next` requests to tell them apart |
| Provider looks perfectly healthy but claims nothing | Its task loop crashed at startup while the rest of the app kept working. Grep the container log from the beginning for a traceback |
| Task fails immediately with a provider error | Provider crashed at runtime; read `docker logs nc_app_<appid>` from the start, not the tail |
| Provider container restarts in a loop | Check the exit code: `137` is the OOM killer; anything else, read the log |
| Providers vanished after an app update | The app is re-registering; they come back when init completes. Verify with the tasktypes endpoint |
| Models re-download after a reinstall | The data volume was removed (`--rm-data`). It holds the models; never use it on an AI app unless you mean it |
| Two apps serve one task type, the wrong one runs | Choose the preferred provider in Administration settings > Artificial intelligence |
| `Failed to get app info for '<id>' from the Appstore` | The app has no release for this Nextcloud version in the store feed; install from its `info.xml` ([ai-stack.md](ai-stack.md)) |
| ExApp enabled but unreachable, heartbeat failures | Not an AI problem: it is the deploy path. See [harp-operations](../../harp-operations/SKILL.md) and [operations.md troubleshooting](../../exapp-operations/references/operations.md#10-troubleshooting-symptom-first) |
| context_chat answers nothing | It needs both the PHP app and its backend ExApp, at compatible versions; check both are installed and initialized |

## Related

- [ai-stack.md](ai-stack.md): install, verify, size and operate.
- [exapp-ai-maintenance.md](../../exapp-maintenance/references/exapp-ai-maintenance.md): change a provider's
  code or add a model, then redeploy it.
- [operations.md](../../exapp-operations/references/operations.md): the ExApp lifecycle underneath.
- Admin manual:
  [insight and debugging](https://docs.nextcloud.com/server/latest/admin_manual/ai/insight_and_debugging.html).
