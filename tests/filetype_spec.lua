-- Regression test for case-insensitive Batch extension detection.
--
-- `vim.filetype.add` wraps pattern keys as '^' .. key .. '$', so a glob such as
-- "*.[bB][aA][tT]" becomes "^*.[bB][aA][tT]$" and can never match.  These
-- assertions fail if the registration regresses to a glob or gains a stray
-- trailing '$'.
--
-- Exercise both registration paths: ftdetect/batch.lua is what lazy.nvim
-- sources at startup, while setup() registers the same patterns again when the
-- plugin is configured.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
dofile(root .. "/ftdetect/batch.lua")

local cases = {
  { "run.bat", "dosbatch" },
  { "RUN.BAT", "dosbatch" },
  { "Run.Bat", "dosbatch" },
  { "build.cmd", "dosbatch" },
  { "BUILD.CMD", "dosbatch" },
  { "Build.Cmd", "dosbatch" },
}

for _, case in ipairs(cases) do
  local name, want = case[1], case[2]
  local got = vim.filetype.match({ filename = "/tmp/" .. name })
  assert(got == want, string.format("%s: expected %s, got %s", name, want, tostring(got)))
end

-- file is not on the runtimepath.
require("batch").setup({})
for _, name in ipairs({ "AFTER.BAT", "after.cmd" }) do
  local got = vim.filetype.match({ filename = "/tmp/" .. name })
  assert(got == "dosbatch", string.format("%s: expected dosbatch after setup(), got %s", name, tostring(got)))
end

print("filetype_spec: OK")
