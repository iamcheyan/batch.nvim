local parser = require("batch.parser")

local M = {}

local function parse_buffer(bufnr)
  return parser.parse(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
end

local function target_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local word = vim.fn.expand("<cword>")
  local target = line:match("[Gg][Oo][Tt][Oo]%s+:([%w_%-]+)")
    or line:match("[Cc][Aa][Ll][Ll]%s+:([%w_%-]+)")
  return target or word
end

local function jump(bufnr, label)
  local item = label and label ~= "" and parse_buffer(bufnr).labels[label:lower()]
  if not item then
    vim.notify("Batch label not found: " .. tostring(label), vim.log.levels.WARN)
    return false
  end
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0, { item.line, 0 })
  vim.cmd("normal! zz")
  return true
end

function M.goto_definition(bufnr)
  bufnr = bufnr or 0
  local target = target_under_cursor()
  return jump(bufnr, target)
end

function M.select_label(bufnr)
  bufnr = bufnr or 0
  local result = parse_buffer(bufnr)
  local choices = {}
  for _, key in ipairs(result.label_order) do
    local item = result.labels[key]
    table.insert(choices, string.format("%04d  :%s", item.line, item.name))
  end
  vim.ui.select(choices, { prompt = "Batch label: " }, function(choice)
    if choice then
      jump(bufnr, choice:match(":([%w_%-]+)$"))
    end
  end)
end

function M.references(bufnr)
  bufnr = bufnr or 0
  local result = parse_buffer(bufnr)
  local target = target_under_cursor():lower()
  local items = {}
  for _, reference in ipairs(result.references) do
    if reference.key == target then
      table.insert(items, {
        bufnr = bufnr,
        lnum = reference.line,
        col = 1,
        text = reference.kind .. " :" .. reference.target,
      })
    end
  end
  vim.fn.setqflist({}, " ", { title = "Batch references: " .. target, items = items })
  vim.cmd("copen")
end

function M.outline(bufnr)
  bufnr = bufnr or 0
  local result = parse_buffer(bufnr)
  local items = {}
  for _, key in ipairs(result.label_order) do
    local item = result.labels[key]
    table.insert(items, {
      bufnr = bufnr,
      lnum = item.line,
      col = 1,
      text = ":" .. item.name,
    })
  end
  vim.fn.setloclist(0, {}, " ", { title = "Batch labels", items = items })
  vim.cmd("lopen")
end

function M.context(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1]
  local current = parser.context(parse_buffer(bufnr), line)
  return current and current.name or "TOP LEVEL"
end

return M
