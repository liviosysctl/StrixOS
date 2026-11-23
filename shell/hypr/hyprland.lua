-- The Hyprland configuration of Strix. modules/desktop/hyprland.nix puts it with the files it requires
-- into /etc/xdg/strix/hypr; HYPRLAND_CONFIG points here, so Hyprland never writes its own.
--
--   machine.lua   keyboard of machine.nix, strix.desktop.extraConfig  (from Nix)
--   theme.lua     window colors of the current theme  (the theme engine, /run/strix/theme)
--   bindings.lua  every key of the cheat sheet  (strix-search bindings, from shell/menu.toml)
--
-- Own settings: strix.desktop.extraConfig in machine.nix, or ~/.config/strix/hyprland.lua,
-- which is read last; Settings writes monitors.lua and keys.lua beside it. Measures and motion come from the design system StrixUI
-- (surfaces.md, motion.md).

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- A laptop's own Full HD screen: Hyprland's "auto" takes 150 % there, which leaves 1280 x 720 and
-- makes everything large and tight. 125 % instead (1536 x 864). Other screens keep "auto", and
-- Settings > Display (monitors.lua, read last) still decides for each one.
for card = 0, 3 do
    for port = 1, 2 do
        local name = "eDP-" .. port
        local file = io.open("/sys/class/drm/card" .. card .. "-" .. name .. "/modes", "r")
        if file then
            local mode = file:read("l")
            file:close()
            if mode == "1920x1080" or mode == "1920x1200" then
                hl.monitor({ output = name, mode = "preferred", position = "auto", scale = 1.25 })
            end
        end
    end
end

hl.config({
    general = {
        -- The grid of the shell: windows stand two steps of four from the screen, the bar and
        -- each other
        gaps_in = 4,
        gaps_out = 8,
        border_size = 1,
        layout = "dwindle",
        resize_on_border = true,
        -- Saturnus until the theme engine has written theme.lua
        col = { active_border = "rgb(712829)", inactive_border = "rgb(2f2c28)" },
    },
    decoration = {
        rounding = 6,
        inactive_opacity = 0.92,
        shadow = { enabled = true, range = 22, render_power = 3, color = 0x80000000 },
        -- Smoked glass: what lies behind a translucent window is blurred, and behind what drops
        -- out of one (menus, the panels of the bar)
        blur = { enabled = true, size = 6, passes = 3, popups = true, popups_ignorealpha = 0.3 },
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

-- Motion. Windows move as in the configuration Strix grew out of: they slide in fast and
-- settle softly (wind), leave with a small swing back (win-out), and workspaces glide the same
-- way. Shell layers only fade here, in the curves of motion.md: the shell animates its own
-- surfaces.
-- On a touchpad, three fingers sideways go to the workspace beside
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

hl.curve("wind", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })
hl.curve("win-in", { type = "bezier", points = { { 0.1, 1.0 }, { 0.1, 1.0 } } })
hl.curve("win-out", { type = "bezier", points = { { 0.3, -0.1 }, { 0, 1 } } })
hl.curve("ease-out", { type = "bezier", points = { { 0.2, 0.8 }, { 0.2, 1 } } })
hl.curve("ease-in", { type = "bezier", points = { { 0.5, 0 }, { 0.9, 0.3 } } })
hl.curve("ease-in-out", { type = "bezier", points = { { 0.65, 0 }, { 0.35, 1 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "wind", style = "slide" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 6, bezier = "win-in", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "win-out", style = "slide" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5, bezier = "wind", style = "slide" })
hl.animation({ leaf = "fade", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 3.6, bezier = "ease-in-out" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 1.4, bezier = "ease-out", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.4, bezier = "ease-in", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.4, bezier = "ease-out" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.4, bezier = "ease-in" })
hl.animation({ leaf = "fadePopupsIn", enabled = true, speed = 1.4, bezier = "ease-out" })
hl.animation({ leaf = "fadePopupsOut", enabled = true, speed = 1.4, bezier = "ease-in" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "wind" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 5, bezier = "wind", style = "slidevert" })

hl.layer_rule({
    -- Smoked glass: what lies behind the surfaces of the shell is blurred. Their clear parts stay
    -- clear, so the bar is still only its buttons on the picture.
    name = "shell-glass",
    match = {
        namespace = "^strix-(bar|dock|search|notifications|osd|clipboard|cheatsheet|switcher|theme-picker)$",
    },
    blur = true,
    blur_popups = true,
    ignore_alpha = 0.3,
})

hl.window_rule({
    -- The system monitor of the bar (strix-monitor) floats in the middle
    name = "system-monitor",
    match = { class = "^strix\\.monitor$" },
    float = true,
    center = true,
    -- Of the screen, so btop gets its 80 columns and it still fits a small or scaled one
    size = "monitor_w*0.9 monitor_h*0.86",
})

hl.window_rule({
    -- What an app opens to ask something floats in the middle instead of taking a tile
    name = "dialogs",
    match = { modal = true },
    float = true,
    center = true,
})

hl.window_rule({
    -- Choosing a file (the portal of GTK), also for apps in a sandbox
    name = "file-chooser",
    match = { class = "^xdg-desktop-portal-gtk$" },
    float = true,
    center = true,
    size = "monitor_w*0.6 monitor_h*0.7",
})

hl.window_rule({
    -- A video taken out of the browser stays on top in the lower right corner, on every workspace
    name = "picture-in-picture",
    match = { title = "^Picture-in-Picture$" },
    float = true,
    pin = true,
    size = "monitor_w*0.25 monitor_h*0.25",
    move = "monitor_w*0.74 monitor_h*0.71",
})

hl.window_rule({
    -- Drawing on a screenshot (strix-capture annotate) is a window over the others
    name = "annotate",
    match = { class = "^com\\.gabm\\.satty$" },
    float = true,
    center = true,
})

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

-- The person's own files in ~/.config/strix, read last: monitors.lua, input.lua and keys.lua are
-- written by Settings (Display, Input, Hotkeys), hyprland.lua is theirs to edit
local home = os.getenv("HOME")
if home then
    for _, name in ipairs({ "monitors", "input", "keys", "hyprland" }) do
        local own = home .. "/.config/strix/" .. name .. ".lua"
        local file = io.open(own, "r")
        if file then
            file:close()
            local ok, err = pcall(dofile, own)
            if not ok then
                print("strix: " .. own .. ": " .. tostring(err))
            end
        end
    end
end
