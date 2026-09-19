vim.bo.commentstring = "REM %s"
vim.bo.omnifunc = "v:lua.require'batch.completion'.omnifunc"
vim.wo.foldmethod = "expr"
vim.wo.foldexpr = "v:lua.require'batch.folding'.foldexpr(v:lnum)"
vim.wo.foldenable = false
