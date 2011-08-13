#!/bin/bash

# download packlist
TMP="$(mktemp)"
wget "http://arutha.rapidspeeds.com:4000/txt" -O "$TMP"

SRC="$TMP"

# print bot's name to stdout
echo "THORA|Arutha"

# grep for packs and print pack numbers to stdout
for i in \
"Wonderful_Days" \
"Bakemonogatari_Ep0[6-9]" \
;do
    grep "$i" "$SRC" | awk '{print $1}' |cut -c 2-
done | tr "\n" " "
echo

# remove temporary file with packlist
rm $TMP
