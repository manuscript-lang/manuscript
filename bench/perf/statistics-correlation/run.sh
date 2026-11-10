#!/usr/bin/env bash
# Alternating before/after process pairs pinned to one CPU; one output file per run in raw/.
# Usage: run.sh <pairs>; expects before-llvm, after-llvm, before-cranelift and after-cranelift here.
set -eu
pairs=${1:-20}
cpu=${CPU:-1}
mkdir -p raw
for be in llvm cranelift; do
	for i in $(seq 1 "$pairs"); do
		if [ $((i % 2)) -eq 1 ]; then order="before after"; else order="after before"; fi
		for v in $order; do
			taskset -c "$cpu" "./$v-$be" >"raw/$be.$v.$i.txt"
		done
	done
done
