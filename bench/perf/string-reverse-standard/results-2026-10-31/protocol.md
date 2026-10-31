# Predeclared standard-iterator reversal experiment

This is a distinct candidate from closed/rejected PR1969. Valid UTF-8 takes a
safe standard-library validation followed by chars().rev().collect::<String>();
the original malformed-input loop and from_buf constructor remain unchanged.
No ASCII special case, representation/ownership change, compiler mechanism,
placement adjustment or padding is introduced. The extra validation pass and
buffer growth may cost time/memory; faster standalone Rust is not acceptance.

Freeze: main98854115f, fixed compiler c0206ad63cab27353feb941a70d4f500dca2856beeb184e4cd98cf3b997a4a85.
Native states baseline/word/reverse/both are rebuilt serially in the same
/workspace/reverse-std-perf path. states.json records exact sources, archives,
all commands/exits and all programs. Every final text producer uses the frozen
compact63-case source with the unchanged oracle/semantics. Earlier unmeasured
input-sized and pre-compaction preparations remain separate.

All build/check work finishes before CPU-0 timings. Run each suite exactly once
with one checked warmup per producer and the balanced rotation/reversal schedule:

- reverse83: four native states + idiomatic Rust, ten rounds,4150rows.
- normalize100: four native states, eight rounds,3200rows.
- byte220: four native states + Rust memchr, ten rounds,11000rows.
- lines16: four native states, eight rounds,512rows.
- text63: four native states + idiomatic Rust, ten rounds,3150rows.

Each variant occupies each position twice. This is balanced, not all possible
permutations for4/5variants. Input setup is outside clocks. The canonical
validator rejects missing/duplicate cases, identity/iteration/checksum mismatch,
invalid times and nonzero exits; each producer additionally guards complete
results. Retain complete raw rows, ranges, per-round paired differences/signs,
all unfavorable cases and partial failures. Verify input/program hashes again
after the full run. Analyze baseline→reverse, word→both, baseline→both,
baseline→word and reverse→both, plus every native→Rust reference where present.

Assess the entire full controls, including early/late Unicode normalization and
all byte prefix boundaries. Reject/hold coherent meaningful common-path or
composition costs rather than trading them away for large reversal gains. A
descriptive threshold or zero flags cannot establish equivalence. Do not run
unchanged repeats to select a favorable acceptance cohort. Independent review
and current-main/final merged-main replay remain necessary before acceptance.

After clocks, record separate single-child peak RSS for ASCII4MiB/mixed5MiB,
five variants baseline/word/reverse/both/Rust, five position-balanced rotations.
Every child must print the exact guarded byte length and exit0. This includes
setup, expected strings and output construction; it is whole-process max RSS,
not allocation count, retained/steady-state memory or allocator diagnosis.
Use the repository's C launcher to avoid Python inherited high-water marks.
No binaries, native archives or helper IR will be published.
