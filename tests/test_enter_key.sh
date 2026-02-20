#!/bin/bash
# test_enter_key.sh
# Check what Enter key sends in raw mode

stty -echo -icanon min 1 time 0
printf "Press Enter (Ctrl+C to quit): "
char=$(dd bs=1 count=1 2>/dev/null)
stty sane
echo
printf "Hex value: "
echo -n "$char" | xxd -p
echo
