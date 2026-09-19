local navigation = require("batch.navigation")

local M = {}

function M.get_info(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  local winid = opts.winid or vim.api.nvim_get_current_win()
  if not vim.tbl_contains({ "dosbatch", "batch" }, vim.bo[bufnr].filetype) then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(winid)[1]
  local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
  local target, kind = text:match("[Gg][Oo][Tt][Oo]%s+:([%w_%-]+)"), "GOTO"
  if not target then
    target, kind = text:match("[Cc][Aa][Ll][Ll]%s+:([%w_%-]+)"), "CALL"
  end
  return {
    format = "BATCH",
    label = navigation.context(bufnr, line),
    line = line,
    target = target,
    target_kind = target and kind or nil,
  }
end

function M.get(opts)
  local info = M.get_info(opts)
  if not info then
    return ""
  end
  local value = string.format("BATCH | LABEL > %s | LINE %d", info.label, info.line)
  if info.target then
    value = value .. string.format(" | %s :%s", info.target_kind, info.target)
  end
  return value
end

function M.component()
  return function()
    return M.get()
  end
end

return M
