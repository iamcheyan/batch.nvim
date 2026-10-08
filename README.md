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
| `:BatchPeek` | 预览穿透：原地浮窗预览 Batch 变量、标签和脚本；在 `.conf` 中递归展开变量并显示最终值 |

`gd` and `gr` mappings are not installed by default. Set `map_keys = true` to
enable those Batch navigation mappings. Peek mappings are controlled separately
by `enable_peek` (enabled by default): `K` / `zp` work in Batch and supported
configuration buffers.

```lua
{
  "iamcheyan/batch.nvim",
  ft = { "dosbatch", "batch", "dosini", "conf" },
  opts = { map_keys = true },
}
```

In Batch files, `K` or `zp` previews variables, `.conf` sources, files, or
`:label` targets. In `dosini` / `conf` configuration buffers, they recursively
expand the current assignment and show the final string, expansion chain, and
definition location. `%NAME%` / `!NAME!` and `${NAME}` are supported.

### Nested config values

Open a `KEY=VALUE` `.conf` file and press `K` anywhere on an assignment line to
expand its left-hand-side variable. If the cursor is on an explicit `%NAME%`,
`!NAME!`, or `${NAME}` reference, `K` expands that referenced variable
instead. The preview shows the final string, expansion chain, source location,
and any unresolved or cyclic references. Expansion is static: the plugin does
not source the file or execute commands.
With `map_keys = true`, Batch buffers also map `gd` to a label definition and
`gr` to label references.

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
