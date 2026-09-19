local config = require("aerial.config")
local util = require("aerial.util")

local M = {}

if not config.batch then
  config.batch = { update_delay = 300 }
end

function M.is_supported(bufnr)
  local filetypes = util.get_filetypes(bufnr)
  for _, filetype in ipairs(filetypes) do
    if filetype == "dosbatch" or filetype == "batch" then
      return true, nil
    end
  end
  return false, "Filetype is not Windows Batch (dosbatch or batch)"
end

function M.fetch_symbols_sync(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local items = {}
  local seen = {}

  for lnum, line in ipairs(lines) do
    local name = line:match("^%s*:([^:][%w_%-]*)%s*$")
    if name and not seen[name:lower()] then
      seen[name:lower()] = true
      table.insert(items, {
        name = ":" .. name,
        kind = "Function",
        lnum = lnum,
        col = 0,
      })
    end
  end

  return items
end

M.fetch_symbols = M.fetch_symbols_sync

return M
