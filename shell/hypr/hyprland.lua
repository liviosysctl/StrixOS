-- The Hyprland configuration of Strix. modules/desktop.nix puts it with the files it requires
-- into /etc/xdg/strix/hypr; HYPRLAND_CONFIG points here, so Hyprland never writes its own.
--
--   machine.lua   keyboard of machine.nix, VMware, strix.desktop.extraConfig  (from Nix)
--   theme.lua     window colors of the current theme  (the theme engine, /run/strix/theme)
--   bindings.lua  every key of the cheat sheet  (strix-search bindings, from shell/menu.toml)
--
-- Own settings: strix.desktop.extraConfig in machine.nix, or ~/.config/strix/hyprland.lua,
-- which is read last. Measures and motion come from the design system StrixUI
-- (surfaces.md, motion.md).

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

hl.config({
    general = {
        gaps_in = 6,
        gaps_out = 12,
        border_size = 1,
        layout = "dwindle",
        resize_on_border = true,
        -- Saturnus until the theme engine has written theme.lua
        col = { active_border = "rgb(712829)", inactive_border = "rgb(2f2c28)" },
    },
    decoration = {
        rounding = 4,
        inactive_opacity = 0.92,
        shadow = { enabled = true, range = 22, render_power = 3, color = 0x80000000 },
        blur = { enabled = false },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    input = {
        follow_mouse = 1,
        touchpad = { natural_scroll = true },
    },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        focus_on_activate = true,
        background_color = 0x0b0a09,
    },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})

-- Motion: the curves and speeds of motion.md. Shell layers only fade here, the shell
-- animates its own surfaces.
hl.curve("ease-out", { type = "bezier", points = { { 0.2, 0.8 }, { 0.2, 1 } } })
hl.curve("ease-in", { type = "bezier", points = { { 0.5, 0 }, { 0.9, 0.3 } } })
hl.curve("ease-in-out", { type = "bezier", points = { { 0.65, 0 }, { 0.35, 1 } } })

hl.animation({ leaf = "windowsIn", enabled = true, speed = 3.6, bezier = "ease-out", style = "popin 86%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.2, bezier = "ease-in", style = "popin 86%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.6, bezier = "ease-in-out" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 3.6, bezier = "ease-out" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 2.2, bezier = "ease-in" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 2.2, bezier = "ease-out" })
hl.animation({ leaf = "fadeShadow", enabled = true, speed = 2.2, bezier = "ease-out" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 2.2, bezier = "ease-out" })
hl.animation({ leaf = "border", enabled = true, speed = 3.6, bezier = "ease-in-out" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 1.4, bezier = "ease-out", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.4, bezier = "ease-in", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.4, bezier = "ease-out" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.4, bezier = "ease-in" })
hl.animation({ leaf = "fadePopupsIn", enabled = true, speed = 1.4, bezier = "ease-out" })
hl.animation({ leaf = "fadePopupsOut", enabled = true, speed = 1.4, bezier = "ease-in" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3.6, bezier = "ease-in-out", style = "slidefade 20%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3.6, bezier = "ease-out", style = "slidefadevert 20%" })

hl.window_rule({
    -- Apps do not maximize themselves over the tiling
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- The parts. One that fails is reported and skipped; the rest still loads.
for _, part in ipairs({ "machine", "theme", "bindings" }) do
    -- read again on every reload: the theme changes while Hyprland runs
    package.loaded[part] = nil
    local ok, err = pcall(require, part)
    if not ok then
        print("strix: " .. part .. ".lua: " .. tostring(err))
    end
end

local home = os.getenv("HOME")
if home then
    local own = home .. "/.config/strix/hyprland.lua"
    local file = io.open(own, "r")
    if file then
        file:close()
        local ok, err = pcall(dofile, own)
        if not ok then
            print("strix: " .. own .. ": " .. tostring(err))
        end
    end
end
