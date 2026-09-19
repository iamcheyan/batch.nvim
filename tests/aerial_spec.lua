local ok_backend, backend = pcall(require, "aerial.backends.batch")
if not ok_backend then
  print("aerial_spec: SKIP (Aerial is not installed)")
  return
end

require("aerial.config").setup({})

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "@echo off",
  ":START_JOB",
  "echo Starting...",
  ":PROCESS_DATA",
  "echo Processing...",
  ":END_JOB",
  "exit /b 0",
})
vim.bo[buf].filetype = "dosbatch"
vim.api.nvim_win_set_buf(0, buf)

backend.fetch_symbols_sync(buf)
local symbols = require("aerial.data").get(buf).items
assert(#symbols == 3, "Aerial backend should expose 3 labels, got " .. tostring(#symbols))
assert(symbols[1].name == ":START_JOB", "Expected :START_JOB, got " .. symbols[1].name)
assert(symbols[2].name == ":PROCESS_DATA", "Expected :PROCESS_DATA, got " .. symbols[2].name)
assert(symbols[3].name == ":END_JOB", "Expected :END_JOB, got " .. symbols[3].name)

print("aerial_spec: OK")
