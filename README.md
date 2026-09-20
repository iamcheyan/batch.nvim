# batch.nvim

Neovim support for Windows Batch files (`.bat` and `.cmd`).

Neovim already provides the basic `dosbatch` syntax highlighting. `batch.nvim`
adds the structural features that are useful when maintaining long operational
scripts: labels, `GOTO`, `CALL :subroutine`, environment variables, return-code
branches, logs, and job-control sections.

## Features

- label and subroutine indexing;
- `GOTO` and `CALL :label` navigation;
- label reference list in the quickfix window;
- label outline in the location list;
- diagnostics for unknown and duplicate labels;
- completion for common `cmd.exe` commands through `omnifunc`;
- label and parenthesized-block folding;
- a reusable statusline component showing the current label and line;
- optional Aerial backend for a sidebar outline.

This plugin does not execute Batch files and does not replace Windows' command
interpreter. It is intended to make large legacy scripts easier to read and
maintain.

## Installation

With lazy.nvim:

```lua
{
  "iamcheyan/batch.nvim",
  ft = { "dosbatch", "batch" },
  opts = {},
}
```

The repository is being developed alongside the
[`night-batch-lab`](https://github.com/iamcheyan/night-batch-lab) practice
project.

## Commands

| Command | Description |
| --- | --- |
| `:BatchCheck` | Rebuild diagnostics for the current file |
| `:BatchJumpToLabel` | Select a label and jump to it |
| `:BatchJumpToLabel name` | Jump to a label by name |
| `:BatchReferences` | List `GOTO`/`CALL` references to the current target |
| `:BatchOutline` | Open the label outline |
| `:BatchPeek` | 预览穿透：原地浮窗预览环境变量定义、.conf 配置来源及调用的外部脚本源码 |

Key mappings are not installed by default. This keeps normal Neovim behavior
unchanged. To use `gd`, `gr`, and `K` / `zp` (预览穿透) for Batch navigation:

```lua
{
  "iamcheyan/batch.nvim",
  ft = { "dosbatch", "batch" },
  opts = { map_keys = true },
}
```

When `map_keys = true`, the following mappings are active in Batch files:
- `K` or `zp`: 原地触发“预览穿透”（Peek Through），如果光标在环境变量上（如 `%NIGHT_VALIDATE_BAT%` 或 `!INPUT_FILE!`），穿透显示赋值语句、`.conf` 键值来源以及被引用文件的真实源码；如果光标在 `:label`，就地预览子程序实现。
- `gd`: 跳转到标签定义。
- `gr`: 查看标签引用列表。

## Statusline

For lualine, Heirline, or a custom statusline. It displays the current label,
line number, and the target on the current `GOTO` or `CALL` line:

```lua
local batch_status = require("batch.statusline")

{ batch_status.component() }
```

## Optional Aerial integration

[Aerial](https://github.com/stevearc/aerial.nvim) is an optional Neovim
sidebar outline plugin. Installing Aerial provides a tree view of Batch labels;
without it, commands, diagnostics, folding, navigation, and completion still
work.

## Scope and limitations

Batch syntax is context-sensitive in ways that are difficult to model without
running `cmd.exe`, especially percent expansion inside parenthesized blocks,
delayed expansion, quoting, and `CALL` double expansion. The first version
therefore reports structural issues only. It is not a complete Batch compiler
or a ShellCheck equivalent.

## Development

```bash
tests/test.sh
```

Use the long-form scripts in `night-batch-lab/windows-batch/` as fixtures. They
contain labels, nested blocks, delayed expansion, explicit return-code checks,
FTP command generation, and ten separately coded jobs.
