if vim.fn.has("nvim") == 1 then
  vim.filetype.add({ extension = { bat = "dosbatch", cmd = "dosbatch" } })
end
