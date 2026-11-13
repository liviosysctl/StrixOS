-- Neovim follows the theme of @name@ (modules/neovim.nix installs this as
-- plugin/@id@.lua). Plugins load after the user's init.lua: a colorscheme
-- chosen there stays.
if vim.g.loaded_@id@_theme then
  return
end
vim.g.loaded_@id@_theme = true

if vim.g.colors_name == nil then
  pcall(vim.cmd.colorscheme, "@id@")
end

-- The theme engine writes tokens.json anew when the god changes (every 10
-- minutes unless kept, or by hand). Every open Neovim takes the new colors at
-- once, as long as it still shows the colorscheme of @name@.
local pending = false
local function reload()
  if pending then
    return
  end
  pending = true
  vim.defer_fn(function()
    pending = false
    if vim.g.colors_name == "@id@" then
      pcall(vim.cmd.colorscheme, "@id@")
    end
  end, 150)
end

local dirs = { "@runtimeDir@" }
if vim.env.XDG_RUNTIME_DIR then
  table.insert(dirs, 1, vim.env.XDG_RUNTIME_DIR .. "/@id@/theme")
end
for _, dir in ipairs(dirs) do
  if vim.uv.fs_stat(dir) then
    local watcher = vim.uv.new_fs_event()
    if watcher then
      watcher:start(dir, {}, function(err, file)
        if not err and file == "tokens.json" then
          vim.schedule(reload)
        end
      end)
    end
  end
end
