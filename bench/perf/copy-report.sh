#!/bin/sh
# usage: copy-report.sh <ms binary> <project ms.toml|file.ms>...
# Counts `copy` instructions in the optimized MIR (what gets compiled; MS_EMIT_OPT=1 ms emit) by
# operand type and by the op that defined the copied value. Every copy of a String retains its
# object today and would allocate if strings became uniquely owned values, so this is the budget
# for that change. Copies of `str` literals are static and free in that model (cap 0); the rest
# are the budget. Set RAW=1 for the unoptimized lowering. Loop membership is not reported.
set -eu
MS=$1; shift
for target in "$@"; do
  out=$(mktemp)
  if [ "${RAW:-0}" = 1 ]; then "$MS" emit "$target" -o "$out" >/dev/null
  else MS_EMIT_OPT=1 "$MS" emit "$target" -o "$out" >/dev/null; fi
  echo "== $target"
  awk '
  /^fn /{delete d}
  /^b[0-9]+\(/{ s=$0; while (match(s,/%[0-9]+: (own )?[^,)]*/)) { id=substr(s,RSTART,RLENGTH); sub(/:.*/,"",id); d[id]="param"; s=substr(s,RSTART+RLENGTH) } }
  /^  %[0-9]+: .* = /{ id=$1; sub(/:/,"",id); line=$0; sub(/^[^=]*= /,"",line); split(line,w," "); op=w[1]; d[id]=op;
    if (op=="copy") { ty=$0; sub(/^ *%[0-9]+: /,"",ty); sub(/ = copy.*/,"",ty); src=w[2]; print ty " <- " (src in d ? d[src] : "?") } }
  ' "$out" | sort | uniq -c | sort -rn
  rm -f "$out"
done
