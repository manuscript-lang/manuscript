[Wiki](../index.md) › [Compiler and build](index.md)

# Standard-library analyses run on demand

Verified: a one-line `print` program imports bundled standard modules through `core.ms`, and analyzing every callable in them dominated `ms check` (measured on the Rust `ms`, 2026-11-14: 60% of 317.5M instructions; on-demand analysis cut it to 167.7M). A callable's analysis does not depend on the program that imports it (its facts come from its body and the summaries of what it calls), so the project's callables are analyzed first and a bundled one when something asks.

- Bodies: `compiler/check/lazy_std.c` sets the bundled standard bodies aside before the body walk and gives one back, checked, only when a checked body names that function or method, until nothing new is named. It applies only to analysis commands (check, lint, the language server): `program->lazy_std` is never set when lowering runs.
- Effects: `compiler/check/effects_scan.c` builds the callable graph from checked bodies and scans from the project callables; a node reached from them is scanned before propagation, since an edge to an unscanned node would read as unknown. A tool that lists library items asks per callable.
- Ownership: result-borrow masks (`compiler/own/result_borrows.c`) and summaries are computed from the project callables plus every callable a summary reads. Interface conversions to a type variable read every implementation's summary, so they use the whole program's methods.
- Rejected probe (Rust era): a bump allocator with no `free` cut `ms check` instructions 26% but made a larger check slower (86 to 110 ms, 26 to 63 MB peak): fresh pages cost more than glibc reuse. Judge allocator changes by wall time and peak RSS, not instructions.

Apply when: adding a program-wide pass over the checked program, or a tool that reads effects or ownership of library callables (ask per callable, do not read the whole table).
Verify: `make conform` unchanged; `ms check` of a hello program does not check every bundled body.
