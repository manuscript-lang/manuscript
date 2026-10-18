# Executable verification performance

`VerifyBuild` reuses the existing streaming `fileDigest` helper instead of
reading the executable into an artifact-sized byte slice. SHA-256 identity,
metadata/source validation and filesystem-error precedence are preserved.
No executable cache or toolchain policy changes.

## Measurement

Production baseline: `aa3efa7296e8b02f1ca1aa26a144debcd69dc7d8`.
Code candidate: `124ec2799dd7d17c983d7689623a5181fcd21c2e`, based on
`7f5834b2129b02e3c7cc1597514f8e34e04b1006`. Intervening #659/#660
do not change the verification functions. Measurements used baseline/candidate
binaries from before that rebase.

Linux 6.18.55 amd64, AMD EPYC 9V74, five visible CPUs, four-CPU cgroup quota,
16 GiB memory limit, pinned Go 1.25.1. Six warm-filesystem samples, one benchmark
CPU; deterministic payloads with independently generated matching metadata:

```sh
toolchain/go/bin/go test ./pkg/build -run '^$' \
  -bench '^BenchmarkVerifyBuild$' -benchmem -benchtime=250ms -count=6 -cpu=1
```

| Payload bytes | Median before | Median after | Allocated before / after |
| --- | ---: | ---: | ---: |
| 1,024 | 11.463 us | 14.718 us | 3,096 / 34,704 B |
| 1,048,576 | 0.959888 ms | 0.861567 ms | 1,058,714 / 34,704 B |
| 8,388,608 | 8.173490 ms | 6.936726 ms | 8,398,746 / 34,704 B |
| 33,554,432 | 36.268211 ms | 31.012701 ms | 33,564,576 / 34,704 B |

The 1 KiB synthetic control costs an additional 3.3 us and 31 KiB because
streaming uses a fixed buffer. Allocations increase from 20 to 24 per call,
while bytes become bounded. Native artifacts of multiple MiB show 10–15% lower
warm verification time.

Peak RSS for one complete four-size benchmark process per version was
108,816 / 43,028 KiB, measured with Python resource.RUSAGE_CHILDREN. This includes
fixture setup and is not per-call RSS. Before-then-after ordering, warm files and
a shared host limit time/RSS claims; no cold-disk or total-build speedup is claimed.

## Validation

- Exact code-head independent gpt-6.1-sol review: no findings;
  `TestVerifyBuild*` passed independently.
- Empty, single-byte, 32 KiB boundary and multi-buffer files are verified;
  changing the final byte is rejected. Missing executables and directory read
  failures retain filesystem errors before metadata-format rejection.
- Existing stale-artifact, source/configuration and native build-type checks
  passed in the integration suite.
- Integration tests passed with `-count=1` for all five assigned packages,
  plus `make repo-check`, scoped `go vet` and Linux amd64 `make dist-check`.
  The packaged CLI used only ms for compilation, source tools, LSP,
  terminal/DAP debugging and profiles, without system Go, dlv or downloads.
- Integration validation used the initial baseline plus the three package
  candidates. Final branch-head review and required CI gate publication/merge;
  these notes do not claim that pending remote CI has passed.

