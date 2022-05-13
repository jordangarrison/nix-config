function map(mode, lhs, rhs, opts)
  local options = { noremap = true }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  vim.api.nvim_set_keymap(mode, lhs, rhs, options)
end

vim.g.mapleader = "<Space>"

map("n", ",<Space>", ":nohlsearch<CR>", { silent = true })
map("n", "<Leader>a", ":cclose<CR>")
map("n", "<Leader>wv", ":VSplit<CR>")
