if vim.fn.has("nvim") == 1 then
  -- `vim.filetype.add` wraps pattern keys as '^' .. key .. '$', so the key must
  -- be a Lua pattern covering the whole file name.  A glob such as
  -- "*.[bB][aA][tT]" becomes "^*.[bB][aA][tT]$", where the leading "*"
  -- quantifies the "^" character and the rule can never match.  Never append a
  -- trailing "$" either: it would be doubled and also fail.
  vim.filetype.add({
    pattern = {
      [".*%.[bB][aA][tT]"] = "dosbatch",
      [".*%.[cC][mM][dD]"] = "dosbatch",
    },
  })
end
