-- This file will not be overwritten across dots-hyprland updates.
-- The file name is for the sake of organization and does not matter
-- See the corresponding files in ~/.config/hypr/hyprland for examples

hl.on("hyprland.start", function ()
    -- AsenaDPI DPI/DNS-bypass tray (eski zapret-tray kaldirildi)
    hl.exec_cmd("sleep 7 && /usr/local/bin/asena-dpi-tray")
    -- Waydroid tray indicator (launch TFT / show full UI / start/restart/stop session)
    hl.exec_cmd("sleep 4 && $HOME/.local/bin/waydroid-tray")
    -- BT profile tray (A2DP <-> HFP toggle, autoswitch kapalı olduğu için manual)
    hl.exec_cmd("sleep 4 && $HOME/.local/bin/bt-tray")
    -- hypridle'i custom config ile yeniden baslat: suspend timeout 90 dk (end-4 ana hypridle.conf'u ezse bile korunur)
    hl.exec_cmd("sleep 4; pkill -x hypridle; hypridle -c $HOME/.config/hypr/custom/hypridle.conf")
    -- ii kilit ekranı yüz tanıma (Howdy) yaması dots güncellemesinde silinmişse kendiliğinden geri yükle.
    -- Master dosyalar: ~/.config/quickshell-custom (apply.sh idempotent; yama varsa dokunmaz)
    hl.exec_cmd("sleep 3; grep -qs faceState $HOME/.config/quickshell/ii/modules/ii/lock/LockSurface.qml || $HOME/.config/quickshell-custom/apply.sh")
    -- dotsync: GitHub'daki kaan-dots ile yerel ayarları karşılaştırır; yalnızca eksik (ve reddedilmemiş)
    -- bir şey varsa eksikler penceresini açar, aksi hâlde sessizdir. Ağ yoksa önbellekle çalışır.
    hl.exec_cmd("sleep 12; $HOME/.local/bin/dotsync boot")
    -- Alt+Tab window switcher (its own Quickshell instance; keys in custom/keybinds.lua)
    hl.exec_cmd("sleep 3; qs -p $HOME/.config/hypr/custom/alttab/shell.qml")
    -- MSI fan/performans kontrolü (MControlCenter), Quickshell'in SNI host'u hazir olsun diye 4sn bekliyor
    hl.exec_cmd("sleep 4 && mcontrolcenter")
end)
