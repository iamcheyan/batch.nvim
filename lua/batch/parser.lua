local M = {}

local function lower(value)
  return value:lower()
end

local function add_variable(result, token, line)
  local key = lower(token)
  local entry = result.variables[key] or {
    name = token,
    lines = {},
  }
  result.variables[key] = entry
  table.insert(entry.lines, line)
  if token:match("^%%%w[%w_]*%%$") then
    result.variables[lower(token:sub(2, -2))] = entry
  end
end

local function add_reference(result, kind, target, line)
  table.insert(result.references, {
    kind = kind,
    target = target,
    key = lower(target),
    line = line,
  })
end

function M.parse(lines)
  local result = {
    lines = lines,
    labels = {},
    label_order = {},
    references = {},
    variables = {},
    line_kinds = {},
  }

  for line_number, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    local label = trimmed:match("^:([^:][%w_%-]*)%s*$")

    if label then
      local key = lower(label)
      if result.labels[key] then
        result.line_kinds[line_number] = "duplicate-label"
      else
        result.labels[key] = { name = label, line = line_number }
        table.insert(result.label_order, key)
        result.line_kinds[line_number] = "label"
      end
    end

    for target in line:gmatch("[Cc][Aa][Ll][Ll]%s+:([%w_%-]+)") do
      add_reference(result, "CALL", target, line_number)
    end
    for target in line:gmatch("[Gg][Oo][Tt][Oo]%s+:([%w_%-]+)") do
      add_reference(result, "GOTO", target, line_number)
    end

    for token in line:gmatch("%%[%~]?[%w_]+%%") do
      add_variable(result, token, line_number)
    end
    for token in line:gmatch("%%~?[%w]+") do
      if token ~= "%%" then
        add_variable(result, token, line_number)
      end
    end
    for name in line:gmatch("!([%w_]+)!") do
      add_variable(result, "!" .. name .. "!", line_number)
    end

    local set_name = line:match("^[%s@]*[Ss][Ee][Tt]%s+[%\"]*([%w_]+)%s*=")
    if set_name then
      result.variables[lower(set_name)] = result.variables[lower(set_name)] or {
        name = set_name,
        lines = {},
      }
      table.insert(result.variables[lower(set_name)].lines, line_number)
    end
  end

  return result
end

function M.diagnostics(result)
  local diagnostics = {}
  local seen_labels = {}

  for line, kind in pairs(result.line_kinds) do
    if kind == "duplicate-label" then
      table.insert(diagnostics, {
        lnum = line - 1,
        col = 0,
        end_col = 1,
        severity = vim and vim.diagnostic.severity.WARN or 2,
        message = "Duplicate Batch label",
        source = "batch.nvim",
      })
    end
  end

  for _, reference in ipairs(result.references) do
    if not result.labels[reference.key] then
      table.insert(diagnostics, {
        lnum = reference.line - 1,
        col = 0,
        end_col = 1,
        severity = vim and vim.diagnostic.severity.ERROR or 1,
        message = string.format("Unknown %s target: :%s", reference.kind, reference.target),
        source = "batch.nvim",
      })
    end
  end

  table.sort(diagnostics, function(a, b)
    return a.lnum < b.lnum
  end)
  return diagnostics
end

function M.context(result, line_number)
  local current
  for _, key in ipairs(result.label_order) do
    local label = result.labels[key]
    if label.line <= line_number then
      current = label
    else
      break
    end
  end
  return current
end

return M
