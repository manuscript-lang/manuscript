# XML delimiter preparation — 2026-11-12

Baseline: `37a14ba5797bed73a66d1350bee03d2238c63a20`, Linux x86-64,
Rust 1.99.1, native LLVM Release. Candidate prepares the delimiter scalar list
once per `Reader.take_until` call. No public API or parsing rules change.

Seven alternating baseline/candidate process pairs on AMD EPYC 9V74 80-Core Processor, pinned to CPU 0, with compilation idle. Input construction is outside timing. The successful
loops measure parse plus complete node equality and a consumed child-count checksum;
error loops check EBADMSG and consume a count. These are not parse-only timings.
Raw observations are in `samples.json` (nanoseconds for `count` calls).

The module copies and both programs were compiled with the same baseline compiler;
the only candidate module difference is the `take_until` body. Both emitted build
metadata report LLVM Release. The baseline and candidate passed all 26 existing
XML tests in Debug; the candidate also passed all 26 in Release. Independent
complete serialized outputs and malformed error kinds matched for empty, short,
Unicode and 10,000-repeat comment/CDATA/attribute/instruction inputs.

Representative median nanoseconds per call:

| Case | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Empty element | 279.4 | 277.1 | -0.8% |
| Ordinary document | 1267.7 | 1238.0 | -2.3% |
| Small comment | 627.1 | 600.3 | -4.3% |
| Empty attribute | 470.8 | 438.7 | -6.8% |
| Comment, about 100k scalars | 3043422.8 | 1861197.3 | -38.8% |
| CDATA, about 100k scalars | 3056307.5 | 1859599.8 | -39.2% |
| Attribute, about 100k scalars | 2716974.5 | 2007637.1 | -26.1% |
| Instruction, about 100k scalars | 2753957.5 | 1942116.8 | -29.5% |
| Missing comment close, about 100k scalars | 2906187.9 | 1849399.4 | -36.4% |

Sizes use `"é日x".repeat(n / 3)`, so nominal 100k is 99,999 scalars.
All measured controls improved or stayed within 1%; no cross-machine or
cross-platform performance claim is made. No instruction or allocation counts
were measured.

To reproduce, build Release compilers and matching runtimes at baseline and
candidate revisions following the repository toolchain guide. Compile this same
probe with each, then run the resulting executables in alternating order, pinned
to one available CPU, without builds running. Compare each case's median elapsed
nanoseconds divided by count; preserve and compare all checksums. Do not time
compiler or build-cache behavior.

Build command: `ms build probe.ms --build-type Release -o probe`. Run the
standalone binaries directly using `taskset -c 0 ./probe` (choose an allowed CPU
on other hosts). Each executable prints CSV: case, count, nanoseconds, checksum.
