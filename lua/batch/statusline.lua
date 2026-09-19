local navigation = require("batch.navigation")

local M = {}

function M.get(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or 0
  if not vim.tbl_contains({ "dosbatch", "batch" }, vim.bo[bufnr].filetype) then
    return ""
  end
  local line = vim.api.nvim_win_get_cursor(opts.winid or 0)[1]
  local context = navigation.context(bufnr, line)
  return string.format("BATCH | LABEL > %s | LINE %d", context, line)
end

function M.component()
  return function()
    return M.get()
  end
end

return M
