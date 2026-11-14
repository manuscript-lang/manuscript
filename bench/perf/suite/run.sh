#!/bin/sh
# General benchmark suite: each program directory holds the same program as main.ms, main.rs, main.go and
# main.js (and main.c where a C control exists). Every sample's output must match the Rust output byte for byte.
# Usage: MS=./target/release/ms sh bench/perf/suite/run.sh [samples] [program ...]
# Table: minimum wall time in ms of N samples (process start, stdin and stdout included; compilation excluded)
# and each language's time over Manuscript's. A missing toolchain leaves its column "-".
set -eu
here=$(cd "$(dirname "$0")" && pwd)
MS=${MS:-ms}
samples=${1:-5}
[ $# -gt 0 ] && shift
work=${BENCH_OUTPUT:-$(mktemp -d)}
mkdir -p "$work"

# name:input-file; "-" means the program takes no input. Inputs come from gen.ms.
manifest=$(grep -v '^#' "$here/manifest.txt" | awk '{print $1":"$3}')
if [ $# -gt 0 ]; then
  picked=""
  for p in "$@"; do picked="$picked $(echo "$manifest" | grep "^$p:" || { echo "unknown program $p" >&2; exit 1; })"; done
  manifest=$(echo $picked | tr ' ' '\n')
fi
if echo "$manifest" | grep -qv ':-$'; then "$MS" run "$here/gen.ms" -- "$work/input" "${SCALE:-1}"; fi

have() { command -v "$1" >/dev/null 2>&1; }
now() { date +%s%N; }
printf '%-12s %8s %8s %8s %8s %8s %8s %8s %8s\n' program ms rust go node c ms/rust ms/go ms/node
for t in $manifest; do
  name=${t%%:*}; input=${t#*:}; d=$here/$name
  "$MS" build "$d/main.ms" -o "$work/${name}_ms" >/dev/null
  [ -f "$d/main.rs" ] && rustc -O -o "$work/${name}_rust" "$d/main.rs"
  have go && [ -f "$d/main.go" ] && (cd "$d" && go build -o "$work/${name}_go" main.go)
  have gcc && [ -f "$d/main.c" ] && gcc -O2 -I"$here" -o "$work/${name}_c" "$d/main.c" -lm
  run() { # run <lang>
    case $1 in
      node) cmd="node $d/main.js" ;;
      *) cmd="$work/${name}_$1" ;;
    esac
    # A directory input is passed as the argument; a file is piped to standard input.
    if [ "$input" = - ]; then $cmd
    elif [ -d "$work/input/$input" ]; then $cmd "$work/input/$input"
    else $cmd <"$work/input/$input"; fi
  }
  # The expected output comes from Rust, or from Go where Rust has no standard-library equivalent.
  ref=rust; [ -x "$work/${name}_rust" ] || ref=go
  run $ref >"$work/$name.expected"
  line="$name"; res=""
  for lang in ms rust go node c; do
    case $lang in
      node) have node && [ -f "$d/main.js" ] || { res="$res -"; continue; } ;;
      *) [ -x "$work/${name}_$lang" ] || { res="$res -"; continue; } ;;
    esac
    best=999999; i=0
    while [ "$i" -lt "$samples" ]; do
      s=$(now); run $lang >"$work/$name.$lang.out"; e=$(now)
      cmp -s "$work/$name.expected" "$work/$name.$lang.out" || { echo "$name: $lang output differs" >&2; exit 1; }
      ms_t=$(( (e - s) / 1000000 )); [ "$ms_t" -lt "$best" ] && best=$ms_t; i=$((i + 1))
    done
    res="$res $best"
  done
  set -- $res
  awk -v n="$name" -v a="$1" -v b="$2" -v g="$3" -v j="$4" -v c="$5" 'BEGIN{
    r = (b > 0) ? sprintf("%.2fx", a / b) : "-"; q = (g > 0) ? sprintf("%.2fx", a / g) : "-"; z = (j > 0) ? sprintf("%.2fx", a / j) : "-"
    printf "%-12s %8s %8s %8s %8s %8s %8s %8s %8s\n", n, a, b, g, j, c, r, q, z }'
done
