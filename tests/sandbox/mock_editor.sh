#!/bin/bash
echo "Mock editor called with $1" >> mock_editor.log
if [ -z "$1" ]; then
    echo "No file argument" >> mock_editor.log
    exit 1
fi
# Append modification to simulate edit
# The TUI passes a temp file path as argument.
echo " [Edited]" >> "$1"
