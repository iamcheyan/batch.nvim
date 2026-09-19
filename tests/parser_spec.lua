local parser = require("batch.parser")

local lines = {
  "@echo off",
  "call :prepare_directories",
  "if errorlevel 1 goto :fatal_error",
  ":prepare_directories",
  "set \"ROOT=%~dp0..\"",
  "goto :done",
  "call :missing_job",
  ":fatal_error",
  ":done",
}

local result = parser.parse(lines)
assert(result.labels.prepare_directories.line == 4, "label line was not indexed")
assert(result.labels.done.line == 9, "second label was not indexed")
assert(#result.references == 4, "GOTO and CALL references were not collected")
assert(result.variables.root.name == "ROOT", "environment variable was not indexed")
assert(result.variables["%~dp0"].name == "%~dp0", "batch argument was not indexed")

local diagnostics = parser.diagnostics(result)
assert(#diagnostics == 1, "unknown label should produce one diagnostic")
assert(diagnostics[1].message:match("missing_job"), "diagnostic target is missing")

print("parser_spec: OK")
