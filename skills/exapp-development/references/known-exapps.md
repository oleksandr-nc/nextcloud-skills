<!--
  - SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
  - SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Known ExApps, examples and libraries

Real ExApps to read when building your own (a production app in your problem domain beats any tutorial), and
the fastest way to find an installed app's source repository when fixing it (the
[exapp-maintenance](../../exapp-maintenance/SKILL.md) skill).

Last verified against: every repository link resolving, on 2026-08-10.

## Nextcloud ExApps using AppAPI

| Name | Language | Description | Link |
|---|---|---|---|
| flow | Python | Nextcloud Flow Engine | [GitHub](https://github.com/nextcloud/flow) |
| llm2 | Python | Local Large Language Model | [GitHub](https://github.com/nextcloud/llm2) |
| stt_whisper2 | Python | Local Whisper Speech-To-Text | [GitHub](https://github.com/nextcloud/stt_whisper2) |
| summary_bot | Python | Summary Bot | [GitHub](https://github.com/nextcloud/summary_bot) |
| talk_bot_ai | Python | Assistant Talk Bot | [GitHub](https://github.com/nextcloud/talk_bot_ai) |
| translate2 | Python | Local Machine Translation | [GitHub](https://github.com/nextcloud/translate2) |
| visionatrix | Python | Scalable AI Provider | [GitHub](https://github.com/cloud-py-api/visionatrix) |

## Example ExApps

| Name | Language | Description | Link |
|---|---|---|---|
| file_to_text_example | Go | Optical image recognition | [GitHub](https://github.com/nextcloud/file_to_text_example) |
| to_gif_example | Python | Simple Files API demo | [GitHub](https://github.com/nextcloud/to_gif_example) |
| upscaler_example | Python | Image upscaler demo | [GitHub](https://github.com/cloud-py-api/upscaler_example) |

The raw-contract reference implementation bundled with this skill is
[assets/minimal_exapp](../assets/minimal_exapp/); `file_to_text_example` is a complete real-world ExApp in Go.

## Wrapper libraries for ExApps

| Name | Language | Description | Link |
|---|---|---|---|
| nc_py_api | Python | Python library for Nextcloud | [GitHub](https://github.com/cloud-py-api/nc_py_api) |

If you wish to develop an application or library, the AppAPI maintainers will gladly help and assist you.
