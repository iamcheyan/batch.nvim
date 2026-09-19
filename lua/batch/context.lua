local M = {}

function M.get_info(opts)
  local info = require("batch.statusline").get_info(opts)
  if not info then
    return nil
  end
  local segments = {
    { text = "LABEL > " .. info.label, hl = "Identifier" },
    { text = "LINE " .. info.line, hl = "Number" },
  }
  if info.target then
    table.insert(segments, {
      text = info.target_kind .. " :" .. info.target,
      hl = "Keyword",
    })
  end
  return {
    language = "BATCH",
    segments = segments,
    source = "batch",
  }
end

return M
