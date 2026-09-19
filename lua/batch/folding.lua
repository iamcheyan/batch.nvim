local M = {}

function M.foldexpr(lnum)
  local line = vim.fn.getline(lnum)
  if line:match("^%s*:[^:]%S*") then
    return ">1"
  end
  if line:match("^%s*[Ii][Ff].*%(%s*$") or line:match("^%s*[Ff][Oo][Rr]%s+.*%(%s*$") then
    return ">2"
  end
  if line:match("^%s*%)%s*$") then
    return "<2"
  end
  return "="
end

return M
