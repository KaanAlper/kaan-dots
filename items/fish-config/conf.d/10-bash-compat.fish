# Bash alışkanlıkları fish'te hata vermesin diye küçük bir uyumluluk katmanı (kaan-dots / "Fish ayarları").
#   $?        -> $status      (fish 4: "$? is not the exit status" ayrıştırma hatası; Enter'a basınca düzeltilir)
#   !!        -> son komut    (örn. `sudo !!`)
#   b '...'   -> bash -c ile çalıştır   (örn. b 'cd /x && python y; echo $?')
#   bp        -> panodaki bash betiğini göster, onay al, bash ile çalıştır (heredoc/for-do-done gibi fish'te
#                çalışmayan çok satırlı betikler için)
# Bağımlılık yok. Kaldırmak için bu dosyayı sil.

status is-interactive; or return

function __bashcompat_fix --description 'tırnak DIŞINDAKİ $? ifadesini $status yap'
    set -l cmd (commandline | string collect)
    string match -q -r -- '\$\?' $cmd; or return
    # Tırnak içindekine dokunma: `b 'echo $?'` gibi bash'e gidecek metin bozulmasın.
    # (`test` yerine switch/string: karşılaştırılan karakter `!` ya da `-a` olunca test bozulur.)
    set -l chars (string split '' -- $cmd)
    set -l n (count $chars)
    set -l out ''
    set -l quote ''
    set -l i 1
    while test $i -le $n
        set -l c $chars[$i]
        if test -n "$quote"
            if string match -q -- $quote $c
                set quote ''
            end
            set out "$out$c"
        else
            switch $c
                case '\\'
                    set out "$out$c"
                    if test $i -lt $n
                        set i (math $i + 1)
                        set out "$out$chars[$i]"
                    end
                case "'" '"'
                    set quote $c
                    set out "$out$c"
                case '$'
                    set -l nxt ''
                    test $i -lt $n; and set nxt $chars[(math $i + 1)]
                    if string match -q -r -- '^\?$' $nxt
                        set out "$out"'$status'
                        set i (math $i + 1)
                    else
                        set out "$out$c"
                    end
                case '*'
                    set out "$out$c"
            end
        end
        set i (math $i + 1)
    end
    commandline -r -- $out
end

function __bashcompat_last_cmd
    echo $history[1]
end
abbr -a '!!' --position anywhere --function __bashcompat_last_cmd

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
# önce $? düzeltmesi, sonra eskiden bağlı olan eylem. Tek seferlik.
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
