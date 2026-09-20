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
  if M.config.map_keys then
    vim.keymap.set("n", "gd", function() navigation.goto_definition(bufnr) end, { buffer = bufnr, desc = "Batch: jump to label" })
    vim.keymap.set("n", "gr", function() navigation.references(bufnr) end, { buffer = bufnr, desc = "Batch: label references" })
    vim.keymap.set("n", "K", function() peek.peek(bufnr) end, { buffer = bufnr, desc = "Batch: peek env variable / label" })
    vim.keymap.set("n", "zp", function() peek.peek(bufnr) end, { buffer = bufnr, desc = "Batch: peek env variable / label" })
  end
  if M.config.enable_diagnostics then
    diagnostics.check(bufnr)
  end
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
  vim.filetype.add({ extension = { bat = "dosbatch", cmd = "dosbatch" } })
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("BatchNvim", { clear = true }),
    pattern = { "dosbatch", "batch" },
    callback = function(args) attach(args.buf) end,
  })
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
  end, { desc = "Peek Batch variable, label or called script", force = true })
end

return M
