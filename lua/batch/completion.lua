local M = {}

local commands = {
  "call", "cd", "copy", "del", "echo", "else", "endlocal", "exit", "for",
  "goto", "if", "mkdir", "move", "pause", "rem", "set", "setlocal", "shift",
  "start", "timeout", "type",
}

function M.omnifunc(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local cursor = vim.api.nvim_win_get_cursor(0)[2]
    local start = cursor
    while start > 0 and line:sub(start, start):match("[%w_%-]" ) do
      start = start - 1
    end
    return start
  end
  local result = {}
  for _, command in ipairs(commands) do
    if command:find(base, 1, true) == 1 then
      table.insert(result, { word = command, menu = "[batch]" })
    end
  end
  return result
end

return M
