# Standalone Rust scalar reversal control

Status: compiled, never executed by this child. No benchmark timings collected.
No production or canonical benchmark source was edited. All deliverables are in
`/workspace/reverse-discovery`.

## Artifacts

- Source: `reverse-control.rs`
- Binary: `rust-reverse-control`
- Build recipe: `build.sh`
- Exact ordered case identities: `inventory.json`
- Input and expected-output SHA256 for each case: `content-identities.json`
- Independent source/corpus audit: `verify-inventory.py`, `inventory-audit.json`
- Toolchain: `rustc-version.txt`
- Source, binary and build-recipe SHA256: `SHA256SUMS`

Source SHA256: `34fa14ecca0f758ced08b7b4ab973289b1ef94956f929648076c713a5dda2a3d`

Binary SHA256: `5e3f74836ec76da1835928aa6fd50ec0aa2fcecea9f88a37efc3f82798fce6ea`

Built with existing Rust 1.99.1 (`58cf8f9c35b355199727627d07ae34a4e2846d67`,
LLVM 23.1.1), x86_64-unknown-linux-gnu, edition 2024, opt-level 3,
overflow checks enabled and frame pointers enabled. No target-cpu override,
dependencies, network, installs, compiler investigation or assembly inspection.

## Exact inventory

All 83 case names, input byte lengths, iteration counts and checksums match
`/workspace/manuscript/bench/perf/string-normalization-rollback/inputs/reverse-full-identities.json`
in order. Audit also matched all nine source pattern name/forward/backward
literals and the iteration arrays against `reverse-full.ms`. Python's independent
code-point reversal matched every constructed explicit expected output.

- `ascii_mixed_nN`, `ascii_controls_nN`: N = 0, 1, 2, 7, 8, 15, 16, 17,
  31, 32, 63, 64, 128, 4096, 1048576 (30 cases).
- `two_byte_copiesN`, `three_byte_copiesN`, `four_byte_copiesN`,
  `mixed_copiesN`, `combining_copiesN`, `zwj_copiesN`,
  `replacement_copiesN`: N = 1, 2, 8, 32, 256, 4096, 65536 (49 cases).
- `late_unicode_N`, `early_unicode_N`: N = 4096, 1048576 (4 cases).

Inputs range from zero to 1,114,112 bytes. Iteration counts depend on byte length:
at most 32 bytes => 1,000,000; at least 262,144 => 16; otherwise at least
4096 => 1024; all remaining cases => 100,000.

Canonical source SHA256:
`e2a3d9649526e85de556a92b3f0fc4ea5f19ee46254ada7b4bfafe41c718c68e`

Canonical identities SHA256:
`97fcce849ce6dcc1bfd614ff21af58ea4be05732c4daa810c05c5f8f6604ddc0`

## Algorithm and later execution

Every operation constructs an owned `String` with
`text.chars().rev().collect::<String>()`. This reverses Unicode scalar order,
including combining marks, NUL, replacement characters and ZWJ sequences.
It does not reverse grapheme clusters. No ASCII-only alternative is included.

All input and expected strings are built before any clock starts. Each case
first checks one complete output, then measures the canonical iteration count.
Every measured output is compared in full with the explicit expected string;
the exact byte-length-plus-17 checksum is consumed and validated. Opaque inputs,
opaque result values, opaque output string views and a non-inline function
prevent dead-code elimination. Result construction, comparison and destruction
are inside the measured interval; setup and printing are outside it.

The parent may later execute:

```sh
/workspace/reverse-discovery/rust-reverse-control --verify
/workspace/reverse-discovery/rust-reverse-control --inventory
/workspace/reverse-discovery/rust-reverse-control > selected-output.csv
```

`--verify` checks all full outputs once without reading a clock; `--inventory`
prints identities without invoking reversal or clocks. No arguments runs the
83-case benchmark with the same CSV header and columns as the Manuscript harness.

Limits: source/corpus checks are complete, but Rust executable correctness is
still pending the parent's untimed `--verify` execution. There is no performance
claim until repeated interleaved runs on the same host and comparable final
builds are collected. The Rust control retains all 83 constructed input/expected
pairs during its process, while the canonical Manuscript harness constructs each
case before measuring it; both exclude setup from the clock. Tiny cases include
the observation/guard overhead. This is an idiomatic owned-String reference,
not a claim of identical allocation strategy or universal language parity.
