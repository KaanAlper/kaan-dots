-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

-- Window close: use Alt+F4 only, remove Super+Q and the "wrong keybind" notify
hl.unbind("SUPER + Q")
hl.unbind("ALT + F4")
hl.bind("ALT + F4", hl.dsp.window.close(), { description = "Window: Close" })

-- Screenshot: PrintScreen → bölge seç (slurp) + swappy (floating editör). Flameshot/Spectacle Wayland'de sorunlu.
hl.unbind("Print")
hl.bind("Print", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | swappy -f -"), { description = "Utilities: Screenshot (slurp+swappy)" })

-- MSI fan toggle — SUPER+F12 yedek, F12 alone başka uygulamalarda kalabilir
-- (Fn+F12 ve F12 Linux'ta aynı keysym üretiyor — donanım Fn'i yutuyor)
hl.bind("SUPER + F12", hl.dsp.exec_cmd("/home/kaanalper/.local/bin/msi-fan-toggle"), { description = "MSI Fan: Toggle Max/Auto" })
