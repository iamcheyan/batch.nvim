if vim.fn.has("nvim") == 1 then
  vim.filetype.add({
    pattern = {
      ["*.[bB][aA][tT]"] = "dosbatch",
      ["*.[cC][mM][dD]"] = "dosbatch",
    },
  })
end
