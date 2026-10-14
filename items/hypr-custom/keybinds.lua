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

-- Alt+Tab window switcher (custom/alttab/shell.qml): hold Alt, Tab moves forward, Shift+Tab back,
-- releasing Alt switches to the selection. Alt itself is bound transparently, so applications still get it.
hl.bind("ALT + Tab", hl.dsp.global("alttab:next"), { description = "Window: Alt+Tab switcher" })
hl.bind("ALT + SHIFT + Tab", hl.dsp.global("alttab:prev"), { description = "Window: Alt+Tab switcher (back)" })
hl.bind("ALT_L", hl.dsp.global("alttab:alt"), { ignore_mods = true, transparent = true })
hl.bind("ALT_R", hl.dsp.global("alttab:alt"), { ignore_mods = true, transparent = true })

-- MSI fan toggle — SUPER+F12 yedek, F12 alone başka uygulamalarda kalabilir
-- (Fn+F12 ve F12 Linux'ta aynı keysym üretiyor — donanım Fn'i yutuyor)
hl.bind("SUPER + F12", hl.dsp.exec_cmd("/home/kaanalper/.local/bin/msi-fan-toggle"), { description = "MSI Fan: Toggle Max/Auto" })
