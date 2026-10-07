-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

-- Waydroid full-UI tek pencere mode'da (multi_windows=false) — normal tile
hl.window_rule({match = {class = "^(Waydroid)$" }, tile = true})
-- Multi-window olursa (Aurora vb.) yine tile
hl.window_rule({match = {class = "^(waydroid\\..*)$" }, tile = true})


-- Performans: blur/shadow/animasyon kapalı (GPU yükü düşer)
hl.window_rule({match = {class = "^(Waydroid|waydroid\\..*)$" }, no_blur = true})
hl.window_rule({match = {class = "^(Waydroid|waydroid\\..*)$" }, no_shadow = true})
hl.window_rule({match = {class = "^(Waydroid|waydroid\\..*)$" }, immediate = true})

-- nchat: yeni mesajda workspace'e otomatik geçişi engelle
hl.window_rule({match = {class = "^(nchat)$" }, no_initial_focus = true})

-- AsenaDPI kontrol penceresi: tiling yerine FLOATING (sabit boyut + ortala koddan gelir) — Discord-popup hissi
hl.window_rule({match = {title = "^(AsenaDPI)$" }, float = true})
hl.window_rule({match = {class = "^(asena-dpi)$" }, float = true})

-- Edge-Drop rules
hl.window_rule({
    match = { class = "^(edge-drop)$" },
    float = true,
    pin = true,
    move = {"0", "0"},
    border_size = 0,
    no_shadow = true,
    rounding = 0,
    no_anim = true,
    no_blur = true,
    no_initial_focus = true,
    opacity = "1.0 1.0"
})
