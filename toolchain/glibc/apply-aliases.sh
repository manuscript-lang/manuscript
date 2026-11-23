#!/bin/sh
# Appends `<primary>` to the data line of every alias in `aliases` whose primary is in the same table:
# `sh apply-aliases.sh <aliases> <table>` rewrites <table> in place. Lines that already name a primary are kept.
set -eu
awk -v file="$1" '
    BEGIN { while ((getline line < file) > 0) if (line !~ /^#/ && split(line, p, " ") == 2) primary[p[1]] = p[2] }
    NR == FNR { if ($4 == "D") defined[$3] = 1; next }
    $4 == "D" && NF == 5 && ($3 in primary) && (primary[$3] in defined) { print $0 " " primary[$3]; next }
    { print }' "$2" "$2" > "$2.tmp"
mv "$2.tmp" "$2"
