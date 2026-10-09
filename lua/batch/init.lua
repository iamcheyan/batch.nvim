local diagnostics = require("batch.diagnostics")
local navigation = require("batch.navigation")
local peek = require("batch.peek")

local M = {}
M.config = {
  enable_diagnostics = true,
  enable_folding = true,
  enable_statusline = true,
  enable_peek = true,
  map_keys = false,
}

M.peek = peek.peek

local function attach(bufnr)
  if vim.b[bufnr].batch_nvim_attached then
    return
  end
  vim.b[bufnr].batch_nvim_attached = true
  vim.bo[bufnr].omnifunc = "v:lua.require'batch.completion'.omnifunc"
  vim.bo[bufnr].commentstring = "REM %s"
  if M.config.enable_folding then
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require'batch.folding'.foldexpr(v:lnum)"
    vim.wo.foldenable = false
  end
  if M.config.enable_peek then
    vim.keymap.set("n", "K", function() peek.peek(bufnr) end, { buffer = bufnr, desc = "Batch: peek env variable / label" })
    vim.keymap.set("n", "zp", function() peek.peek(bufnr) end, { buffer = bufnr, desc = "Batch: peek env variable / label" })
  end
  if M.config.map_keys then
    vim.keymap.set("n", "gd", function() navigation.goto_definition(bufnr) end, { buffer = bufnr, desc = "Batch: jump to label" })
    vim.keymap.set("n", "gr", function() navigation.references(bufnr) end, { buffer = bufnr, desc = "Batch: label references" })
  end
  if M.config.enable_diagnostics then
    diagnostics.check(bufnr)
  end
end

local function attach_config(bufnr, probe_line)
  if vim.b[bufnr].batch_nvim_config_attached then return end
  if not peek.is_config_buffer(bufnr, probe_line) then return end
  vim.b[bufnr].batch_nvim_config_attached = true
  if M.config.enable_peek then
    vim.keymap.set("n", "K", function() peek.peek(bufnr) end, { buffer = bufnr, desc = "Batch: expand config variable" })
    vim.keymap.set("n", "zp", function() peek.peek(bufnr) end, { buffer = bufnr, desc = "Batch: expand config variable" })
  end
end

local function is_extensionless_text_buffer(bufnr)
  local filetype = vim.bo[bufnr].filetype
  if filetype ~= "" and filetype ~= "text" then return false end
  local name = vim.fs.basename(vim.api.nvim_buf_get_name(bufnr))
  return not name:find("%.", 2)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  local ok_contextline, contextline = pcall(require, "contextline")
  if ok_contextline then
    contextline.register("batch", {
      filetypes = { "dosbatch", "batch" },
      get_info = require("batch.context").get_info,
    })
  end
  -- Lua patterns, not globs: `vim.filetype.add` anchors these as '^' .. pat .. '$'.
  vim.filetype.add({
    pattern = {
      [".*%.[bB][aA][tT]"] = "dosbatch",
      [".*%.[cC][mM][dD]"] = "dosbatch",
    },
  })
  local group = vim.api.nvim_create_augroup("BatchNvim", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "dosbatch", "batch", "dosini", "conf", "sh", "text" },
    callback = function(args)
      if args.match == "dosbatch" or args.match == "batch" then
        attach(args.buf)
      else
        attach_config(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    group = group,
    callback = function(args) attach_config(args.buf) end,
  })
  vim.api.nvim_create_autocmd("TextChanged", {
    group = group,
    callback = function(args)
      local buf = args.buf
      if vim.b[buf].batch_nvim_config_attached then return end
      if is_extensionless_text_buffer(buf) then attach_config(buf) end
    end,
  })
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = group,
    callback = function(args)
      local buf = args.buf
      if vim.b[buf].batch_nvim_config_attached or not is_extensionless_text_buffer(buf) then return end
      local line = buf == vim.api.nvim_get_current_buf() and vim.api.nvim_get_current_line() or nil
      if peek.is_setenv_line(line) then attach_config(buf, line) end
    end,
  })
  local current_buf = vim.api.nvim_get_current_buf()
  if vim.bo[current_buf].filetype == "dosbatch" or vim.bo[current_buf].filetype == "batch" then
    attach(current_buf)
  else
    attach_config(current_buf)
  end
  vim.api.nvim_create_user_command("BatchCheck", function(args)
    diagnostics.check(args.buf)
  end, { desc = "Check Batch labels and references", force = true })
  vim.api.nvim_create_user_command("BatchJumpToLabel", function(args)
    if args.args ~= "" then
      local result = require("batch.parser").parse(vim.api.nvim_buf_get_lines(args.buf, 0, -1, false))
      local item = result.labels[args.args:lower()]
      if item then
        vim.api.nvim_win_set_cursor(0, { item.line, 0 })
      else
        vim.notify("Batch label not found: " .. args.args, vim.log.levels.WARN)
      end
    else
      navigation.select_label(args.buf)
    end
  end, { nargs = "?", desc = "Jump to a Batch label", force = true })
  vim.api.nvim_create_user_command("BatchReferences", function(args)
    navigation.references(args.buf)
  end, { desc = "List references to the current Batch label", force = true })
  vim.api.nvim_create_user_command("BatchOutline", function(args)
    navigation.outline(args.buf)
  end, { desc = "Open Batch label outline", force = true })
  vim.api.nvim_create_user_command("BatchPeek", function(args)
    peek.peek(args.buf)
  end, { desc = "Peek Batch targets or expand config variables", force = true })
end

return M
