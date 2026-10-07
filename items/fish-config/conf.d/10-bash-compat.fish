# Bash alışkanlıkları fish'te hata vermesin diye uyumluluk katmanı (kaan-dots / "Fish ayarları").
#
# Enter'a basınca komut satırı taranır (tırnak içi hariç):
#   $?                          -> $status
#   $!                          -> $last_pid
#   [[ ]], ;do/;then/;done/;fi, -> komut `bash -c '...'` olarak yeniden yazılır (bash'e yönlendirilir)
#   <<heredoc, ${VAR}, $((x)),     NOT: bash'e yönlendirilen komutun cd/export gibi yan etkileri fish
#   `backtick`, $'..', f() {}      oturumuna GEÇMEZ (çocuk süreçte çalışır). Normal fish komutlarına dokunulmaz.
#   !!                          -> son komut (örn. `sudo !!`)
# Yardımcılar: b '...' (bash -c)  ·  bp (panodaki bash betiğini onayla + çalıştır)  ·  unset VAR
# Bağımlılık yok. Kaldırmak için bu dosyayı sil.

status is-interactive; or return

function __bashcompat_fix --description 'Enter öncesi: bash-ism düzelt ya da bash`e yönlendir'
    set -l cmd (commandline | string collect)
    # Hızlı ön eleme: sıradan komutlarda tarama maliyeti yok.
    string match -q -r -- '\$[?!]|\[\[|;\s*(do|then|done|fi|esac)\b|^\s*(done|fi|esac)\b|<<|\$\(\(|\$\{|`|\$\x27|^\s*\w+\(\)\s*\{' $cmd; or return

    # Tek geçiş: out = $?/$! çevrilmiş kopya; all = her iki tırnağın içi boşaltılmış; sng = yalnız tek tırnak içi boşaltılmış.
    # (`test` yerine switch/string: karşılaştırılan karakter `!` ya da `-a` olunca test bozulur.)
    set -l chars (string split '' -- $cmd)
    set -l n (count $chars)
    set -l out ''
    set -l all ''
    set -l sng ''
    set -l quote ''
    set -l skip 0
    set -l i 1
    while test $i -le $n
        set -l c $chars[$i]
        if test -n "$quote"
            if string match -q -- $quote $c
                set quote ''
                set all "$all$c"
                set sng "$sng$c"
            else if string match -q -- '"' $quote
                set all "$all "
                set sng "$sng$c"
            else
                set all "$all "
                set sng "$sng "
            end
            set out "$out$c"
        else
            switch $c
                case '\\'
                    set -l nx ''
                    test $i -lt $n; and set nx $chars[(math $i + 1)]
                    set out "$out$c$nx"
                    set all "$all$c$nx"
                    set sng "$sng$c$nx"
                    set i (math $i + 1)
                case "'" '"'
                    set quote $c
                    set out "$out$c"
                    set all "$all$c"
                    set sng "$sng$c"
                case '$'
                    set -l nx ''
                    test $i -lt $n; and set nx $chars[(math $i + 1)]
                    set all "$all$c"
                    set sng "$sng$c"
                    if string match -q -r -- '^\?$' $nx
                        set out "$out"'$status'
                        set skip 1
                    else if string match -q -r -- '^!$' $nx
                        set out "$out"'$last_pid'
                        set skip 1
                    else
                        set out "$out$c"
                    end
                case '*'
                    if test $skip -eq 1
                        set skip 0
                    else
                        set out "$out$c"
                    end
                    set all "$all$c"
                    set sng "$sng$c"
            end
        end
        set i (math $i + 1)
    end

    set -l bashy 0
    if string match -q -r -- '\[\[|;\s*(do|then|done|fi|esac)\b|^\s*(done|fi|esac)\b|<<|^\s*\w+\(\)\s*\{' $all
        set bashy 1
    else if string match -q -r -- '\$\(\(|\$\{|`|\$\x27' $sng
        set bashy 1
    end

    if test $bashy -eq 1
        # Zaten bash/sh ile başlıyorsa dokunma.
        string match -q -r -- '^\s*(sudo\s+)?(bash|sh|zsh|dash|fish|b|bp)\b' $all; and return
        commandline -r -- "bash -c "(string escape --style=script -- $cmd)
        return
    end

    test "$out" != "$cmd"; and commandline -r -- $out
end

function __bashcompat_last_cmd
    echo $history[1]
end
abbr -a '!!' --position anywhere --function __bashcompat_last_cmd

function unset --description 'bash unset: değişkeni sil'
    set -e $argv
end

function b --description 'argümanı bash -c ile çalıştır'
    bash -c "$argv"
end

function bp --description 'panodaki bash betiğini onayla ve bash ile çalıştır'
    set -l script (wl-paste 2>/dev/null | string collect)
    if test -z "$script"
        echo "bp: pano boş" >&2
        return 1
    end
    echo "── panodaki betik ──────────────────────────"
    printf '%s\n' $script
    echo "────────────────────────────────────────────"
    read -l -P "bash ile çalıştırılsın mı? [e/H] " yn
    if test "$yn" = e -o "$yn" = E
        printf '%s\n' $script | bash
    end
end

# Enter bağını, diğer her şey (starship geçici prompt vb.) yüklendikten SONRA, ilk prompt'ta sar:
# önce bash-ism düzeltmesi, sonra eskiden bağlı olan eylem. Tek seferlik.
# Not: `execute` gibi giriş fonksiyonları fish komutu değildir; `commandline -f` ile çağrılır.
function __bashcompat_install --on-event fish_prompt
    functions -e __bashcompat_install
    set -q __bashcompat_installed; and return
    set -g __bashcompat_installed 1
    set -l input_fns (bind --function-names)
    for key in enter ctrl-j
        set -l orig (bind $key 2>/dev/null | tail -n 1 | string replace -r '^bind (?:--\S+ )*\S+ ' '')
        test -n "$orig"; or set orig execute
        if contains -- $orig $input_fns
            set orig "commandline -f $orig"
        end
        bind $key "__bashcompat_fix; $orig"
    end
end
