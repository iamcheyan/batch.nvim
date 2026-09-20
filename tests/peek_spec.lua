local peek = require("batch.peek")

-- Test 1: Target extraction
local target1 = peek.extract_target_under_cursor('call "%NIGHT_VALIDATE_BAT%" "%INPUT_FILE%"', 15)
assert(target1, "Target 1 should not be nil")
assert(target1.type == "variable", "Target 1 should be a variable")
assert(target1.name == "NIGHT_VALIDATE_BAT", "Target 1 name should be NIGHT_VALIDATE_BAT")

local target2 = peek.extract_target_under_cursor("if errorlevel 1 goto :error_input", 25)
assert(target2, "Target 2 should not be nil")
assert(target2.type == "label", "Target 2 should be a label")
assert(target2.name == "error_input", "Target 2 name should be error_input")

local target3 = peek.extract_target_under_cursor("set \"CSV2XLS_JS=%CSV2XLS_CONVERTER%\"", 22)
assert(target3, "Target 3 should not be nil")
assert(target3.type == "variable", "Target 3 should be variable")
assert(target3.name == "CSV2XLS_CONVERTER", "Target 3 name should be CSV2XLS_CONVERTER")

-- Test 1b: File targets and cursor on extension/filename
local conf_line = 'set "CONFIG_FILE=%~dp0night-batch.conf"'
-- Cursor on 'conf' (col 37)
local target_conf_ext = peek.extract_target_under_cursor(conf_line, 37)
assert(target_conf_ext, "target_conf_ext should not be nil")
assert(target_conf_ext.type == "file", "target_conf_ext should be file type: " .. tostring(target_conf_ext.type))
assert(target_conf_ext.name == "night-batch.conf", "target_conf_ext name should be night-batch.conf: " .. tostring(target_conf_ext.name))
assert(target_conf_ext.raw == "%~dp0night-batch.conf", "target_conf_ext raw should be %~dp0night-batch.conf: " .. tostring(target_conf_ext.raw))

-- Cursor on 'night-batch' (col 25)
local target_conf_base = peek.extract_target_under_cursor(conf_line, 25)
assert(target_conf_base and target_conf_base.type == "file" and target_conf_base.name == "night-batch.conf", "target_conf_base mismatch")

-- Cursor on 'CONFIG_FILE' (col 10) should be recognized as variable
local target_conf_var = peek.extract_target_under_cursor(conf_line, 10)
assert(target_conf_var and target_conf_var.type == "variable" and target_conf_var.name == "CONFIG_FILE", "target_conf_var mismatch")

-- Call with bat file
local bat_call_line = 'call "%~dp0load-config.bat" "%CONFIG_FILE%"'
local target_bat = peek.extract_target_under_cursor(bat_call_line, 15)
assert(target_bat and target_bat.type == "file" and target_bat.name == "load-config.bat", "target_bat mismatch")

-- Test 2: Full resolution with fixture if available
local fixture_path = vim.env.BATCH_NVIM_FIXTURE
if not fixture_path or vim.fn.filereadable(fixture_path) == 0 then
  print("peek_spec: OK (basic extraction verified, fixture skipped)")
  return
end

-- Create a scratch buffer with the fixture file
local bufnr = vim.fn.bufadd(fixture_path)
vim.fn.bufload(bufnr)

-- Resolve file peek for night-batch.conf directly (simplified format: Path only on line 1)
local file_res = peek.resolve_file_peek(bufnr, target_conf_ext)
assert(file_res, "file_res should not be nil")
assert(file_res.lines[1]:find("Path: windows%-batch/night%-batch%.conf"), "file_res line 1 should mention Path: " .. tostring(file_res.lines[1]))
assert(file_res.lines[2]:find("───"), "file_res line 2 should be separator: " .. tostring(file_res.lines[2]))
assert(file_res.lines[3]:find("# Shared training"), "file_res line 3 should be first code line: " .. tostring(file_res.lines[3]))
assert(file_res.target_file, "file_res target_file should be resolved")
assert(file_res.target_file:find("night%-batch%.conf"), "file_res target_file should point to night-batch.conf")
assert(#file_res.lines > 5, "file_res lines should include file content")
assert(#file_res.links >= 1, "file_res should have clickable links")

-- Resolve CONFIG_FILE (assigned in script via %~dp0night-batch.conf)
local config_file_res = peek.resolve_variable_peek(bufnr, "CONFIG_FILE")
assert(config_file_res, "config_file_res should not be nil")
assert(config_file_res.target_file, "config_file_res target_file should be resolved")
assert(config_file_res.target_file:find("night%-batch%.conf"), "config_file_res target_file should point to night-batch.conf")

-- Resolve NIGHT_VALIDATE_BAT (assigned via conf)
local var_res = peek.resolve_variable_peek(bufnr, "NIGHT_VALIDATE_BAT")
assert(var_res, "var_res should not be nil")
assert(var_res.lines[1]:find("NIGHT_VALIDATE_BAT"), "line 1 should mention variable name: " .. tostring(var_res.lines[1]))
assert(var_res.lines[2]:find("Source:"), "line 2 should show source: " .. tostring(var_res.lines[2]))
assert(var_res.lines[3]:find("Value:"), "line 3 should show value: " .. tostring(var_res.lines[3]))
assert(var_res.target_file, "target_file should be resolved")
assert(var_res.target_file:find("validate%-input%.bat"), "target_file should point to validate-input.bat")
assert(#var_res.lines > 5, "lines should include file content")
assert(#var_res.links >= 1, "var_res should have clickable links")

-- Resolve label
local label_res = peek.resolve_label_peek(bufnr, "usage")
if not label_res then
  label_res = peek.resolve_label_peek(bufnr, "process_job")
end
assert(label_res, "label_res should not be nil")
assert(label_res.lines[1]:find("Label:"), "line 1 of label peek should mention label")
assert(#label_res.lines > 1, "label lines should be populated")

-- Test 3: Double-K direct jump test (file peek)
-- Switch to buffer and set cursor to line 18, col 36 (the 'conf' extension)
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_win_set_cursor(0, { 18, 36 })

-- 1st K: opens floating window
local win = peek.peek(bufnr)
assert(win and vim.api.nvim_win_is_valid(win), "Floating window should be opened on 1st K")
local float_buf = vim.api.nvim_win_get_buf(win)
local float_lines = vim.api.nvim_buf_get_lines(float_buf, 0, -1, false)
assert(#float_lines > 5, "Float buffer should contain preview lines")
assert(float_lines[1]:find("Path: windows%-batch/night%-batch%.conf"), "Float line 1 should have Path: " .. float_lines[1])
assert(float_lines[2]:find("───"), "Float line 2 should have separator: " .. float_lines[2])
assert(float_lines[3]:find("# Shared training"), "Float line 3 should have first code line: " .. float_lines[3])

-- 2nd K: immediately executes direct jump to target file
peek.peek(bufnr)
local active_buf = vim.api.nvim_get_current_buf()
local active_buf_name = vim.api.nvim_buf_get_name(active_buf)
assert(active_buf_name:find("night%-batch%.conf"), "Active buffer after 2nd K should be night-batch.conf: " .. active_buf_name)

-- Test 4: Variable peek with 'o' key direct jump (e.g. %CSV2XLS_CSV_DIR% -> night-batch.conf:17)
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_win_set_cursor(0, { 33, 15 }) -- line 33 is CSV_DIR=%CSV2XLS_CSV_DIR%
local csv_win = peek.peek(bufnr)
assert(csv_win and vim.api.nvim_win_is_valid(csv_win), "CSV2XLS_CSV_DIR peek window should open")
local csv_buf = vim.api.nvim_win_get_buf(csv_win)
local csv_lines = vim.api.nvim_buf_get_lines(csv_buf, 0, -1, false)
assert(csv_lines[1]:find("Variable: %%CSV2XLS_CSV_DIR%%"), "Line 1 should mention Variable: " .. csv_lines[1])
assert(csv_lines[2]:find("Source: windows%-batch/night%-batch%.conf:17"), "Line 2 should show night-batch.conf:17: " .. csv_lines[2])
assert(csv_lines[3]:find("Value: @ROOT@\\data\\input\\csv"), "Line 3 should show Value: " .. csv_lines[3])

-- Press 'o' directly from main buffer to jump to source definition
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("o", true, false, true), "x", false)
local source_buf = vim.api.nvim_get_current_buf()
local source_buf_name = vim.api.nvim_buf_get_name(source_buf)
assert(source_buf_name:find("night%-batch%.conf"), "Buffer after 'o' jump should be night-batch.conf: " .. source_buf_name)
local cursor_pos = vim.api.nvim_win_get_cursor(0)
assert(cursor_pos[1] == 17, "Cursor line should jump to line 17 in night-batch.conf, got: " .. tostring(cursor_pos[1]))

-- Test 5: Variable peek with Double-K jump (e.g. %CSV2XLS_LOG_DIR% -> night-batch.conf:21)
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_win_set_cursor(0, { 37, 15 }) -- line 37 is LOG_DIR=%CSV2XLS_LOG_DIR%
local log_win = peek.peek(bufnr)
assert(log_win and vim.api.nvim_win_is_valid(log_win), "LOG_DIR peek window should open on 1st K")
local log_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(log_win), 0, -1, false)
assert(log_lines[1]:find("Variable: %%CSV2XLS_LOG_DIR%%"), "Log line 1 Variable")
assert(log_lines[2]:find("night%-batch%.conf:21"), "Log line 2 Source night-batch.conf:21")

-- 2nd K: double-K jump to line 21 of night-batch.conf
peek.peek(bufnr)
local log_target_buf = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_buf_get_name(log_target_buf):find("night%-batch%.conf"), "Buffer after double-K should be night-batch.conf")
local log_pos = vim.api.nvim_win_get_cursor(0)
assert(log_pos[1] == 21, "Cursor should jump to line 21 in night-batch.conf, got: " .. tostring(log_pos[1]))

print("peek_spec: OK")
