local parser = require("batch.parser")

local M = {}
M.namespace = vim.api.nvim_create_namespace("batch_nvim_diagnostics")

function M.check(bufnr)
  bufnr = bufnr or 0
  local result = parser.parse(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  vim.diagnostic.set(M.namespace, bufnr, parser.diagnostics(result), {})
  return result
end

return M
