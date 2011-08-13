#!/bin/bash

# download packlist
TMP="$(mktemp)"
TMP2="$(mktemp)"
wget "http://www.sailormooncenter.net/3/xdcc_list" -O "$TMP2"
awk '/Usagi packlist/, /\/pre/' "$TMP2" > "$TMP"
rm $TMP2

SRC="$TMP"

# print bot's name to stdout
echo "SMC|Usagi"

# grep for packs and print pack numbers to stdout
for i in \
" Sailor Moon S [1C]" \
"Sailor Moon Sailor Stars Hero Club" \
;do
    grep "$i" "$SRC" | awk '{print $1}' |cut -c 2-
done | tr "\n" " "
echo

# remove temporary file with packlist
rm $TMP
