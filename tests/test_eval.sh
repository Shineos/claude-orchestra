#!/bin/bash
set -euxo pipefail

test_eval() {
    local options_str="$1"
    local num_options=0
    
    local OLDIFS="$IFS"
    IFS=' '
    for opt_value in $options_str; do
        echo "Processing: $opt_value"
        eval "local OPT_$num_options=\"\$opt_value\""
        echo "Set OPT_$num_options"
        num_options=$((num_options + 1))
    done
    IFS="$OLDIFS"
}

echo "Testing eval with set -e..."
test_eval "Auto(AI) frontend backend"
echo "Success"
