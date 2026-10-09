local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)/tests/[^/]+$")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local peek = require("batch.peek")
local test_dir = vim.fn.tempname() .. "-setenv-config"
vim.fn.mkdir(test_dir, "p")
local env_path = test_dir .. "/environment"
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, env_path)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'setenv ROOT_DIR "/path/to/root"',
  'setenv WORK_DIR "$ROOT_DIR/work"',
  'setenv OUTPUT_DIR "$WORK_DIR/output"',
})
vim.bo[buf].filetype = "text"
assert(not env_path:match("%.[^/]+$"), "fixture must have no extension")
assert(peek.is_config_buffer(buf), "an extensionless setenv file should be recognized as a config buffer")

local setenv_line = vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]
local lhs_col = setenv_line:find("OUTPUT_DIR", 1, true) + 2
local lhs = peek.extract_target_under_cursor(setenv_line, lhs_col)
assert(lhs and lhs.type == "variable" and lhs.name == "OUTPUT_DIR", "K on setenv LHS should choose the assigned variable")
local ref_col = setenv_line:find("$WORK_DIR", 1, true) + 3
local ref = peek.extract_target_under_cursor(setenv_line, ref_col)
assert(ref and ref.type == "variable" and ref.name == "WORK_DIR" and ref.explicit, "bare $NAME references should be recognized explicitly")

local preview = peek.resolve_config_variable_peek(buf, "OUTPUT_DIR")
assert(preview, "setenv variable should resolve")
assert(preview.lines[2] == "Value: /path/to/root/work/output", "nested $NAME references should expand: " .. tostring(preview.lines[2]))
assert(preview.lines[3] == "Expansion: OUTPUT_DIR → $WORK_DIR/output → $ROOT_DIR/work → /path/to/root/work/output",
  "preview should show each source expansion step: " .. tostring(preview.lines[3]))

vim.api.nvim_set_current_buf(buf)
vim.api.nvim_win_set_cursor(0, { 3, lhs_col - 1 })
local float_win = peek.peek(buf)
assert(float_win and vim.api.nvim_win_is_valid(float_win), "K-style peek should open for extensionless setenv config")
local float_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float_win), 0, -1, false)
assert(float_lines[2] == "Value: /path/to/root/work/output", "floating preview should show the fully expanded value")
vim.api.nvim_win_close(float_win, true)

require("batch").setup({ enable_diagnostics = false, enable_folding = false })
local function has_peek_map(target)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(target, "n")) do
    if map.lhs == "K" and map.desc == "Batch: expand config variable" then return true end
  end
  return false
end
assert(has_peek_map(buf), "K peek map should attach to an extensionless setenv config buffer")

local new_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(new_buf, test_dir .. "/new-environment")
vim.bo[new_buf].filetype = "text"
vim.api.nvim_exec_autocmds("BufNewFile", { buffer = new_buf })
assert(not has_peek_map(new_buf), "empty extensionless text buffers should not be claimed as config")
vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, { 'setenv ROOT_DIR "/tmp/root"' })
vim.api.nvim_set_current_buf(new_buf)
vim.api.nvim_exec_autocmds("TextChangedI", { buffer = new_buf })
assert(has_peek_map(new_buf), "a newly typed setenv directive should activate config peek")

vim.fn.delete(test_dir, "rf")
print("setenv_config_spec: OK")
