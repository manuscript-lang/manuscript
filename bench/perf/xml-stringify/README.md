# XML stringify child inspection

Issue [#3400](https://github.com/manuscript-lang/manuscript/issues/3400): `stringify`
used to inspect every child's tag and collected text even when compact
output ignored the answer, and kept inspecting after finding mixed content. The
fix skips this formatting decision for compact output and stops at its first
positive result. The predicate, escaping and output remain unchanged.

## 2026-11-10

- Baseline: main `2050d2b4f56bc9851cb58c17f6eabb125610e7a2`. Candidate: the
  guard/break change in `stdlib/data/xml.ms` accompanying this page.
- Linux x86-64, AMD EPYC 9V74, 5 visible vCPUs, approximately 17 GiB RAM.
  Fresh source-built Rust 1.99.1 Release compiler; native Cranelift Release programs.
- Fifteen alternating before/after pairs pinned to CPU 0. Both modules compiled
  through the same local import and probe paths. Parsing/construction is untimed;
  each timed call compares the full output against an independently constructed
  expected string and contributes its byte length to a checked checksum.
- Raw samples and per-case records remain local and uncommitted. Minor/major
  faults describe the complete process: median 1,663 minor faults on each side,
  zero major faults. Independent review recomputed all 19 medians, ratios and
  checksums from the 570 local samples.

Selected medians in nanoseconds per serialization:

| Case | Before | After | After/before |
| --- | ---: | ---: | ---: |
| Empty | 66.83 | 64.06 | 0.959 |
| One child | 131.18 | 126.79 | 0.967 |
| 2,048 attributed long-name elements, compact | 333,993 | 313,870 | 0.940 |
| Same elements, indented | 365,951 | 364,717 | 0.997 |
| Text before those elements, indented | 334,248 | 310,579 | 0.929 |
| Text after those elements, indented | 333,013 | 342,028 | 1.027 |
| 98,304-byte Unicode text, compact | 18,799 | 17,409 | 0.926 |
| 1,024 comments, compact | 41,663 | 23,033 | 0.553 |
| Same comments, indented | 55,000 | 54,132 | 0.984 |

The small last-text difference is within local run variability; this is a focused
performance improvement, not a claim about overall XML speed or other hosts.
The latest broad [baseline](../baseline-2026-10-28.md) has no XML stringify case;
these fresh paired measurements provide the relevant comparison.

The deterministic [allocation fixture](../../../tests/ownership-counts/xml_stringify.ms)
requests 27 allocations / 90,509 bytes in native Cranelift Debug before the fix
and 25 / 82,317 after it. Cranelift Release changes 28 / 90,525 to 26 / 82,333.
Both variants exit with zero live runtime blocks. This catches the redundant
4,096-byte text copies without a timing threshold. Instruction counts were
unavailable: Valgrind was absent and its package probe failed; no installation
or access restriction was bypassed.

Reproduce from the repository root on Linux after building `ms`:

```sh
python3 bench/perf/xml-stringify/run.py --ms target/release/ms --pairs 15 --cpu 0
```

The driver writes binaries, source snapshots, raw timings, summary and hashes to
`.artifacts/xml-stringify/`. `--before` selects a baseline revision and `--output`
selects an independent output directory. Run the allocation fixture with
`ms run tools/count-check.ms -- tests/ownership-counts/xml_stringify.ms`.

The driver passed syntax validation, but its native smoke build stopped before
execution because the default runtime cache was read-only. That operation was
not retried. The measurements above came from the original paired run, which
used an explicitly configured workspace cache from the start.
