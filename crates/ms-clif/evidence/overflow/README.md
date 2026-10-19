# Checked arithmetic if-conversion evidence

Base: `aa884e9a` (includes #781 and #778). Ownership checked before implementation:
#781, `chinmaymk`, `claude/ms-codegen`, pure-diamond implementation; merged as
`c802c995` during this work. This change extends that pass, rather than duplicating it.
No other open PR covered overflow flags or DWARF when inspected.

## Collatz

Linux x86_64, Rust 1.99.1, Cranelift 0.136.0, Go 1.25.1. Input:
`crates/ms-clif/kernels/collatz.mir`, one million starts, checksum **524**.
All native versions use MIR `speed`, CLIF `speed`, checks and polling enabled,
frame pointers, PIC, the same C test runtime (`cc -O2 -fno-omit-frame-pointer`),
and the same linker. Compiler executables were built with the dev profile;
compiler build time is excluded. Go uses the existing kernel's `collatz` function
with `fmt.Println(collatz(1000000))`, built with `-trimpath -buildvcs=false` and no
special optimization flags. Go is context: it has no Manuscript overflow/poll checks.

One warmup per binary, then twenty trials per binary, rotating and reversing
process order, pinned to CPU 0, no simultaneous compilation. Every invocation
must exit zero and print exactly 524. Raw samples, input/binary hashes, and
environment are in [collatz.json](collatz.json). Median whole-process seconds:

| Version | Seconds |
| --- | ---: |
| Main before #781 (`85d49f16`) | 0.407478 |
| #781 alone (`2e2fad0a`) | 0.408210 |
| This overflow change | 0.285944 |
| Handwritten Go | 0.263228 |

The candidate took about 30% less time than #781 alone on this kernel and machine,
and about 1.09 times the Go time. This is not a general speed or Go-parity claim.
Predictable branches and other operand distributions can lose from speculative
work. The original four-instruction arm budget bounds expansion, not profitability.

Controls were built from archived source into a separate Cargo target directory.
The pre-#781 and #781-alone generated object bytes were identical (SHA-256
`b184f9abb708718f8d13dd91177ac9d27fde1edccd90a7db99fa9d11cefd217b`).
The candidate object differed. This identity check caught and invalidated an
earlier comparison whose shared Cargo example output path selected the candidate
as its own control. Those invalid samples are excluded.

Build each source revision in its own checkout and **its own** `CARGO_TARGET_DIR`:

```sh
cargo build -p ms-clif --example mirc
target/debug/examples/mirc crates/ms-clif/kernels/collatz.mir -o collatz --dump-clif
objdump -d collatz
```

Inspect the candidate's inner loop: one signed multiply with `seto`, one add with
`seto`, two masked cold overflow guards, and a conditional move for the parity
choice. The adjacent flag/result lowering shares the arithmetic instruction;
the earlier experiment emitted the multiplication twice.

Rejected preliminary experiment: flag computation with the original value branch
still present. [rejected-spike.json](rejected-spike.json) retains its twelve
exploratory samples: baseline 0.421s, flag+branch 0.551s, flag+select 0.339s medians.
These samples included compiler activity and are only directional experiment
history, not controlled performance evidence. The standalone preparation pass was
rejected; the retained implementation requires and extends #781's conversion.

## Validation and review

- All ms-mir/ms-clif tests; fmt; clippy with warnings denied.
- Interpreter parity over 9×9×2 signed boundary/branch combinations, including
  first-fault text and source; text roundtrip; untaken overflow; triangle form;
  full inline scope; unchanged Debug pipeline.
- Reject calls, effects, polls, ownership and trapping division. Positive literal
  divisors accepted; zero and negative divisors rejected for speculation.
- Native optimized/unoptimized codegen: first overflowing multiply/add locations,
  MIN×-1, negative/zero values, untaken overflows, LIFO cleanup, and checks disabled.
- Real runtime: an inlined overflowing converted function retains both frames.
- Independent Sol proposal/implementation review challenged do-nothing, duplicate
  arithmetic, trapping speculation, source/order, Debug, and benchmark controls.
  Its conditional acceptance requirements above were exercised successfully.

This commit is independent of the subsequent DWARF line-table commit.
