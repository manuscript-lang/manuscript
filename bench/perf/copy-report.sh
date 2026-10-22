#!/bin/sh
# usage: copy-report.sh <ms binary> <project ms.toml|file.ms>...
# Counts `copy` instructions in the lowered MIR (ms emit) by operand type. Every copy of a
# String retains its object today and would allocate if strings became uniquely owned values,
# so this is the static budget for that change. Loop membership is not reported.
set -eu
MS=$1; shift
for target in "$@"; do
  out=$(mktemp)
  "$MS" emit "$target" -o "$out" >/dev/null
  echo "== $target"
  grep ' = copy ' "$out" | sed -E 's/^ *%[0-9]+: ([^=]*) = copy.*/\1/' | sort | uniq -c | sort -rn
  rm -f "$out"
done
