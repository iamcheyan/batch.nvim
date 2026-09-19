local parser = require("batch.parser")
local fixture_path = vim.env.BATCH_NVIM_FIXTURE
if not fixture_path or vim.fn.filereadable(fixture_path) == 0 then
  print("night_batch_spec: SKIP (BATCH_NVIM_FIXTURE is not available)")
  return
end
local fixture = vim.fn.readfile(fixture_path)
local result = parser.parse(fixture)

assert(result.labels.process_job, "night-batch-lab process label was not found")
assert(result.labels.upload_ftp, "night-batch-lab FTP label was not found")
assert(result.labels.job_error, "night-batch-lab error label was not found")
assert(#result.references >= 10, "explicit job references were not indexed")
assert(result.variables.upload_mode, "UPLOAD_MODE was not indexed")

print("night_batch_spec: OK")
