# Tool speed on large inputs, 2026-11-18

Release `ms` from `make build` at `138bca14` (before) and this branch (after), 4 vCPU Xeon VM, wall-clock medians of 3 runs unless noted. Inputs come from `bench/perf/compile-scaling/functions.py N` (13 lines per function): 8000 functions is 136k lines, 32000 is 544k lines. Instruction counts are whole-process callgrind totals.

Before this page, every tool measured linear in input size (`ms check` 1.4 s at 136k lines, 5.3 s at 544k). The gaps below are constant-factor and parallelism, found by profiling each tool.

| tool | input | before | after | change |
| --- | --- | --- | --- | --- |
| `ms fmt --check` | 8000 functions | 2.40 s | 1.99 s | fewer passes over the text |
| `ms fmt --check` | 32000 functions | 10.4 s | 8.4 s | same |
| `ms fmt` (callgrind) | 1000 functions | 1.62 G instr | 1.27 G instr | -21% |
| `ms fmt --check .` | 8 files of 2000 functions | 3.28 s | 0.89 s | files format on every core |
| `ms diagram --format html` | 8000 functions | 4.37 s | 3.37 s | no second compile |
| LSP completion with a prefix | 34k-line file, 700k lines of siblings | 1.31 s | 0.26 s | siblings with no matching `export` line are not parsed |

What changed:

- Formatter: the token-to-position and bracket-pair tables are a binary search and a flat array instead of SipHash maps (the two maps were 10% of the instructions), the remaining maps use the compiler's Fx hasher (`ms-syntax/src/fxmap.rs`, moved from `ms-check`), and `format_lines` no longer parses text it parses again on the next line.
- `ms diagram --format html` asked the language server for type hints by compiling the file again; it now builds that analysis from the program it already checked (output byte-identical on `tools/close-matrix.ms` and the 8000-function file).
- LSP completion re-parsed every sibling file on each keystroke to learn its exports. A line scan for `export` (a superset test: a top-level declaration starts its line with `export` and names itself on it) skips the parse for files that cannot match.
- `ms fmt` over several files used one core and stopped scaling at two because every name lookup took the interner mutex. A lookup of a known name probes the table without the lock; only a new name locks. Four cores: 2.93 s on one CPU, 1.70 s on two, 0.89 s on four (`taskset`).

Findings with no change (numbers for the next round):

- `ms check` is single-threaded (`user` equals `real`) and its profile is flat: checking 39%, ownership 32%, parsing 14%, malloc and free about 20% of all instructions at 34k lines. The checker holds `Rc` types, so spreading it over cores is a redesign.
- Release (LLVM) builds are dominated by `opt` and `llc`: 31 s of 37 s for 136k lines. A 900-line `yaml.ms` test emits 412k lines of LLVM IR in 6 units (12 CPU-s, 5.8 s wall); `flow_value`, 328 source lines, is 42k IR lines, a fifth of it `getelementptr`. Changing the MIR inliner's growth factor from 4 to 2 left the IR size unchanged, so the size comes from lowering, not inlining.
- `ms build` has no build cache: an unchanged file rebuilds in the same time (0.75 s for 17k lines in Debug).
