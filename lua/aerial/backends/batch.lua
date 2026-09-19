local backend_util = require("aerial.backends.util")
local backends = require("aerial.backends")
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

local function get_line_len(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, true)[1] or ""
  return #line
end

local function set_end_range(bufnr, items, last_line)
  if not last_line then
    last_line = vim.api.nvim_buf_line_count(bufnr)
  end
  local prev = nil
  for _, item in ipairs(items) do
    if prev then
      prev.end_lnum = item.lnum - 1
      prev.end_col = get_line_len(bufnr, prev.end_lnum)
    end
    prev = item
  end
  if prev then
    prev.end_lnum = last_line
    prev.end_col = get_line_len(bufnr, last_line)
  end
end

function M.fetch_symbols_sync(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local items = {}
  local seen = {}

  for lnum, line in ipairs(lines) do
    local name = line:match("^%s*:([^:%s]+)")
    if name and not seen[name:lower()] then
      seen[name:lower()] = true
      local col = (line:find(":" .. name, 1, true) or 1) - 1
      local item = {
        name = ":" .. name,
        kind = "Function",
        lnum = lnum,
        col = col,
        level = 0,
      }
      if
        not config.post_parse_symbol
        or config.post_parse_symbol(bufnr, item, { backend_name = "batch", lang = "batch" }) ~= false
      then
        table.insert(items, item)
      end
    end
  end

  set_end_range(bufnr, items)
  backends.set_symbols(bufnr, items, { backend_name = "batch", lang = "batch" })
  return items
end

M.fetch_symbols = M.fetch_symbols_sync

M.attach = function(bufnr)
  backend_util.add_change_watcher(bufnr, "batch")
end

M.detach = function(bufnr)
  backend_util.remove_change_watcher(bufnr, "batch")
end

return M
