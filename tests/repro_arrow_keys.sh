#!/bin/bash
source "$(dirname "$0")/../.claude/scripts/tui-keyboard.sh"

echo "Press arrow keys (Ctrl-C to exit)..."
while true; do
    key=$(tui_get_key)
    if [[ "$key" == "TIMEOUT" ]]; then continue; fi
    if [[ "$key" == "EOF" ]]; then break; fi
    
    # Debug raw hex output
    printf "Key: %q\n" "$key"
    
    if [[ "$key" == "$KEY_RIGHT" ]]; then
        echo "Detected: RIGHT ARROW"
    elif [[ "$key" == "$KEY_LEFT" ]]; then
        echo "Detected: LEFT ARROW"
    elif [[ "$key" == $'\x1b[' ]]; then
        echo "Detected: BROKEN SEQUENCE (ESC [)"
    fi
done
