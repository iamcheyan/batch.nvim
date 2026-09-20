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

-- Test 2: Full resolution with fixture if available
local fixture_path = vim.env.BATCH_NVIM_FIXTURE
if not fixture_path or vim.fn.filereadable(fixture_path) == 0 then
  print("peek_spec: OK (basic extraction verified, fixture skipped)")
  return
end

-- Create a scratch buffer with the fixture file
local bufnr = vim.fn.bufadd(fixture_path)
vim.fn.bufload(bufnr)

-- Resolve NIGHT_VALIDATE_BAT (assigned via conf)
local var_res = peek.resolve_variable_peek(bufnr, "NIGHT_VALIDATE_BAT")
assert(var_res, "var_res should not be nil")
assert(var_res.title:find("NIGHT_VALIDATE_BAT"), "title should mention NIGHT_VALIDATE_BAT")
assert(var_res.target_file, "target_file should be resolved")
assert(var_res.target_file:find("validate%-input%.bat"), "target_file should point to validate-input.bat")
assert(#var_res.lines > 5, "lines should include file content")

-- Resolve label
local label_res = peek.resolve_label_peek(bufnr, "usage")
if not label_res then
  label_res = peek.resolve_label_peek(bufnr, "process_job")
end
assert(label_res, "label_res should not be nil")
assert(#label_res.lines > 1, "label lines should be populated")

print("peek_spec: OK")
