if vim.g.loaded_batch_nvim then
  return
end
vim.g.loaded_batch_nvim = true

require("batch").setup()
