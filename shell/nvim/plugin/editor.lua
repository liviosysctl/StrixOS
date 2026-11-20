-- Neovim for people who are new to it (modules/neovim.nix installs this as
-- plugin/@id@-editor.lua, with the plugins it sets up): a menu that says what
-- the keys do, a start page, a file tree, a finder, a line that names the
-- mode, completion, and the keys other editors have taught (Ctrl S saves).
-- Space is the leader: press it and wait a moment for the menu.
-- Space ? or F1 shows the cheat sheet (@id@/cheatsheet.txt).
-- Whoever brings an own configuration (init.lua or init.vim) gets Neovim as it
-- is: nothing here runs.
if vim.g.loaded_@id@_editor then
  return
end
vim.g.loaded_@id@_editor = true

local own = vim.fn.stdpath("config")
if vim.uv.fs_stat(own .. "/init.lua") or vim.uv.fs_stat(own .. "/init.vim") then
  return
end

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- ------------------------------------------------------------------ options
local o = vim.opt
o.number = true
o.mouse = "a"
-- Copying and pasting use the clipboard of the desktop
o.clipboard = "unnamedplus"
-- Leaving with changes asks whether to save, instead of refusing
o.confirm = true
-- Undo still works after closing and opening a file
o.undofile = true
o.ignorecase = true
o.smartcase = true
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.wrap = false
o.signcolumn = "yes"
o.cursorline = true
o.scrolloff = 8
o.sidescrolloff = 8
o.splitbelow = true
o.splitright = true
-- The status line names the mode
o.showmode = false
o.updatetime = 250
-- How long the menu of keys waits
o.timeoutlen = 300
o.termguicolors = true

-- ------------------------------------------------------------------ keys
local function map(mode, keys, action, desc, opts)
  opts = opts or {}
  opts.desc = desc
  vim.keymap.set(mode, keys, action, opts)
end

map("i", "jk", "<Esc>", "Leave insert mode")
map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><Esc>", "Save")
map("n", "<Esc>", "<cmd>nohlsearch<cr>", "Clear the search marks")
-- In wrapped lines, up and down go by what is seen
map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", "Down", { expr = true, silent = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", "Up", { expr = true, silent = true })
-- Indenting keeps the selection
map("x", "<", "<gv", "Indent less")
map("x", ">", ">gv", "Indent more")

map("n", "<leader>w", "<C-w>", "Windows", { remap = true })
map("n", "<C-h>", "<C-w>h", "Window to the left")
map("n", "<C-j>", "<C-w>j", "Window below")
map("n", "<C-k>", "<C-w>k", "Window above")
map("n", "<C-l>", "<C-w>l", "Window to the right")

map("n", "<leader>qq", "<cmd>qa<cr>", "Quit")
map("n", "<leader>Q", "<cmd>qa!<cr>", "Quit without saving")
map("n", "<leader>fn", "<cmd>enew<cr>", "New file")
map("n", "<leader>fs", "<cmd>w<cr>", "Save")

map("n", "<S-h>", "<cmd>bprevious<cr>", "File to the left")
map("n", "<S-l>", "<cmd>bnext<cr>", "File to the right")
map("n", "<leader>bd", "<cmd>bdelete<cr>", "Close this file")

map("n", "<leader>cd", vim.diagnostic.open_float, "What is wrong in this line")
map("n", "<leader>cr", vim.lsp.buf.rename, "Rename")
map("n", "<leader>ca", vim.lsp.buf.code_action, "Suggested fixes")
map("n", "<leader>cf", function()
  vim.lsp.buf.format({ async = true })
end, "Format the file")
map("n", "gd", vim.lsp.buf.definition, "Go to the definition")

map("n", "<leader>ht", "<cmd>Tutor<cr>", "The tutorial (30 minutes)")

-- ------------------------------------------------------------------ the cheat sheet
-- A window in the middle with the keys worth knowing; q or Esc closes it
local function cheatsheet()
  local file = vim.api.nvim_get_runtime_file("@id@/cheatsheet.txt", false)[1]
  if not file then
    return
  end
  local lines = vim.fn.readfile(file)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].bufhidden = "wipe"
  local width = math.min(88, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 6)
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2) - 1,
    style = "minimal",
    border = "rounded",
    title = " Neovim keys: j and k scroll, q closes ",
    title_pos = "center",
  })
  vim.wo[window].cursorline = false
  -- Headings, and the keys in the first column
  vim.fn.matchadd("Title", [[^\S.*$]], 10, -1, { window = window })
  vim.fn.matchadd("Special", [[^  \zs\S.\{-}\ze  ]], 10, -1, { window = window })
  for _, keys in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", keys, "<cmd>close<cr>", { buffer = buffer, nowait = true })
  end
end
vim.api.nvim_create_user_command("Cheatsheet", cheatsheet, { desc = "The keys worth knowing" })
map("n", "<leader>?", cheatsheet, "Cheat sheet")
map({ "n", "i" }, "<F1>", cheatsheet, "Cheat sheet")

-- ------------------------------------------------------------------ the plugins
-- Each is set up only if it is there: a system without one still starts
local function with(name, setup)
  local ok, plugin = pcall(require, name)
  if ok then
    setup(plugin)
  end
end

-- The menu of keys: after Space, g, z, d and the like
with("which-key", function(keys)
  keys.setup({ preset = "modern", delay = 300 })
  keys.add({
    { "<leader>f", group = "Find and files" },
    { "<leader>s", group = "Search" },
    { "<leader>g", group = "Git" },
    { "<leader>c", group = "Code" },
    { "<leader>b", group = "Open files" },
    { "<leader>h", group = "Help" },
    { "<leader>q", group = "Quit" },
  })
end)

-- The finder
with("telescope", function(telescope)
  telescope.setup({
    defaults = {
      layout_strategy = "horizontal",
      layout_config = { prompt_position = "top" },
      sorting_strategy = "ascending",
    },
  })
  local find = require("telescope.builtin")
  map("n", "<leader><space>", find.find_files, "Find a file")
  map("n", "<leader>ff", find.find_files, "Find a file")
  map("n", "<leader>fg", find.live_grep, "Find text in all files")
  map("n", "<leader>fb", find.buffers, "Open files")
  map("n", "<leader>fr", find.oldfiles, "Recent files")
  map("n", "<leader>fw", find.grep_string, "The word under the cursor")
  map("n", "<leader>sk", find.keymaps, "All keys")
  map("n", "<leader>sc", find.commands, "All commands")
  map("n", "<leader>sd", find.diagnostics, "Problems")
  map("n", "<leader>sr", find.resume, "The last search again")
  map("n", "<leader>hh", find.help_tags, "The manual")
  map("n", "<leader>gc", find.git_commits, "Commits")
  map("n", "<leader>gs", find.git_status, "Changed files")
end)

-- The file tree
with("neo-tree", function(tree)
  tree.setup({
    close_if_last_window = true,
    filesystem = {
      follow_current_file = { enabled = true },
      filtered_items = { visible = true, hide_dotfiles = false },
    },
    window = {
      position = "left",
      width = 30,
      mappings = { ["l"] = "open", ["h"] = "close_node" },
    },
  })
  map("n", "<leader>e", "<cmd>Neotree toggle<cr>", "File tree")
end)

-- The line at the bottom: the mode, the file, the position
with("lualine", function(line)
  line.setup({ options = { globalstatus = true, disabled_filetypes = { statusline = { "alpha" } } } })
end)

-- Open files as tabs at the top, once there is more than one
with("bufferline", function(tabs)
  tabs.setup({
    options = {
      always_show_bufferline = false,
      offsets = { { filetype = "neo-tree", text = "Files", highlight = "Directory", text_align = "left" } },
    },
  })
end)

-- Changed lines marked at the left, in a Git repository
with("gitsigns", function(signs)
  signs.setup()
end)

-- A bracket or a quote brings its partner
with("mini.pairs", function(pairs)
  pairs.setup()
end)

-- Completion while typing: Tab and Shift Tab choose, Enter takes
with("blink.cmp", function(completion)
  completion.setup({
    keymap = {
      preset = "enter",
      ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
      ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
    },
    completion = { documentation = { auto_show = true } },
  })
end)

-- Colors by the grammar of the language, where its parser is installed
vim.api.nvim_create_autocmd("FileType", {
  callback = function(event)
    pcall(vim.treesitter.start, event.buf)
  end,
})

-- Nix: mistakes underlined while typing, and the file formatted on saving
if vim.fn.executable("nil") == 1 and vim.lsp.config then
  vim.lsp.config("nil_ls", {
    cmd = { "nil" },
    filetypes = { "nix" },
    root_markers = { "flake.nix", ".git" },
    settings = { ["nil"] = { formatting = { command = { "nixfmt" } } } },
  })
  vim.lsp.enable("nil_ls")
  vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*.nix",
    callback = function(event)
      if #vim.lsp.get_clients({ bufnr = event.buf, name = "nil_ls" }) > 0 then
        vim.lsp.buf.format({ bufnr = event.buf, timeout_ms = 1000 })
      end
    end,
  })
end

-- The start page, when Neovim opens without a file
with("alpha", function(alpha)
  local page = require("alpha.themes.dashboard")
  page.section.header.val = { "@name@   Neovim" }
  page.section.buttons.val = {
    page.button("f", "  Find a file", "<cmd>Telescope find_files<cr>"),
    page.button("n", "  New file", "<cmd>enew<cr>"),
    page.button("r", "  Recent files", "<cmd>Telescope oldfiles<cr>"),
    page.button("e", "  File tree", "<cmd>Neotree toggle<cr>"),
    page.button("?", "  Cheat sheet", "<cmd>Cheatsheet<cr>"),
    page.button("t", "  Tutorial, 30 minutes", "<cmd>Tutor<cr>"),
    page.button("q", "  Quit", "<cmd>qa<cr>"),
  }
  page.section.footer.val = "Space opens the menu of keys. i writes, Esc stops writing, Ctrl S saves."
  alpha.setup(page.config)
end)
