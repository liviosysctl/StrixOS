-- The languages of a Strix machine in Neovim (modules/apps/neovim.nix installs this as
-- plugin/@id@-languages.lua): mistakes underlined while typing, completion with what a name
-- means, Space c f to format. Nix for the configuration, Lua for Hyprland (the own keys and
-- settings in ~/.config/@id@), TOML for themes and menus.
-- Whoever brings an own configuration (init.lua or init.vim) gets Neovim as it is.
if vim.g.loaded_@id@_languages or not vim.lsp.config then
  return
end
vim.g.loaded_@id@_languages = true

local own = vim.fn.stdpath("config")
if vim.uv.fs_stat(own .. "/init.lua") or vim.uv.fs_stat(own .. "/init.vim") then
  return
end

local config_dir = "@configDir@"

-- Nix: the options of NixOS and of the distribution suggested with what they do (nixd reads them
-- from the configuration of this machine), and the file formatted on saving
if vim.fn.executable("nixd") == 1 then
  local machine = '(builtins.getFlake "' .. config_dir .. '")'
  vim.lsp.config("nixd", {
    cmd = { "nixd" },
    filetypes = { "nix" },
    root_markers = { "flake.nix", ".git" },
    settings = {
      nixd = {
        nixpkgs = { expr = "import " .. machine .. ".inputs.@id@.inputs.nixpkgs { }" },
        options = { nixos = { expr = machine .. ".nixosConfigurations.@id@.options" } },
        formatting = { command = { "nixfmt" } },
      },
    },
  })
  vim.lsp.enable("nixd")
  vim.api.nvim_create_autocmd("BufWritePre", {
    pattern = "*.nix",
    callback = function(event)
      if #vim.lsp.get_clients({ bufnr = event.buf, name = "nixd" }) > 0 then
        vim.lsp.buf.format({ bufnr = event.buf, timeout_ms = 2000 })
      end
    end,
  })
end

-- Lua: Hyprland's own functions (hl.bind, hl.config, ...) known with their arguments, from the
-- descriptions Hyprland comes with; in Neovim's own files also vim.*
if vim.fn.executable("lua-language-server") == 1 then
  local library = {}
  if "@hyprStubs@" ~= "" then
    table.insert(library, "@hyprStubs@")
  end
  vim.lsp.config("lua_ls", {
    cmd = { "lua-language-server" },
    filetypes = { "lua" },
    root_markers = { ".luarc.json", ".git" },
    settings = {
      Lua = {
        runtime = { version = "Lua 5.4" },
        workspace = { library = library, checkThirdParty = false },
        diagnostics = { globals = { "hl", "vim" } },
        telemetry = { enable = false },
      },
    },
  })
  vim.lsp.enable("lua_ls")
end

-- TOML: themes (theme.toml), menus, Cargo.toml, checked while typing
if vim.fn.executable("taplo") == 1 then
  vim.lsp.config("taplo", {
    cmd = { "taplo", "lsp", "stdio" },
    filetypes = { "toml" },
    root_markers = { ".taplo.toml", "taplo.toml", ".git" },
  })
  vim.lsp.enable("taplo")
end
