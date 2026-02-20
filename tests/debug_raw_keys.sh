#!/bin/bash
# tests/debug_raw_keys.sh - 実際にターミナルでどのバイトが飛んでいるかを確認する

cleanup() {
    stty sane
    tput cnorm
    echo -e "\nRestored terminal."
    exit
}

trap cleanup SIGINT

echo "Press keys to see hex values (Press Ctrl+C to quit)"
stty -echo -icanon time 0 min 1
tput civis

while true; do
    char=$(dd bs=1 count=1 2>/dev/null)
    if [[ -n "$char" ]]; then
        printf "Char: [%s] Hex: %s\n" "$char" "$(printf '%s' "$char" | xxd -p)"
    fi
done
