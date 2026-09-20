local M = {}

function M.get_info(opts)
  local info = require("batch.statusline").get_info(opts)
  if not info then
    return nil
  end
  -- A top-level line with no target has no useful code context.  In
  -- particular, do not keep an otherwise empty contextline winbar visible
  -- merely because the status component knows the current line number.
  if info.label == "TOP LEVEL" and not info.target then
    return nil
  end
  local segments = {}
  if info.label and info.label ~= "" then
    table.insert(segments, {
      text = info.label,
      label = "label",
      icon = "󰊕",
      icon_hl = "Function",
      hl = "Function",
      type = "symbol",
    })
  end
  if info.line then
    table.insert(segments, {
      text = "L" .. info.line,
      label = "line",
      icon = "󰎠",
      icon_hl = "Number",
      hl = "Number",
      type = "symbol",
    })
  end
  if info.target then
    table.insert(segments, {
      text = info.target_kind .. " :" .. info.target,
      label = "target",
      icon = "󰌗",
      icon_hl = "Keyword",
      hl = "Keyword",
      type = "symbol",
    })
  end
  return {
    language = "BATCH",
    segments = segments,
    source = "batch",
  }
end

return M
