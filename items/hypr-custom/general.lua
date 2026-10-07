-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

hl.config({
    input = {
        kb_layout = "tr",
        touchpad = {
            disable_while_typing = false,
        },
    }
})

-- eDP-1'i 60Hz'e sabitle (pil tasarrufu); hyprland/general.lua'daki
-- "preferred" (240Hz) catch-all kuralini ezer. 240Hz'e donmek icin bu
-- blogu sil veya mode = "2560x1600@240" yap.
hl.monitor({
    output = "eDP-1",
    mode = "2560x1600@60",
    position = "0x0",
    scale = "1"
})
