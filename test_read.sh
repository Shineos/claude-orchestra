#!/bin/bash
stty -icanon -echo
printf "1文字入力してください: "
read -rsn1 char
stty icanon echo
echo
echo "入力された文字: $char"
echo "長さ: ${#char}"
