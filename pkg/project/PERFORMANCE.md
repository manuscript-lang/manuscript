# Project discovery performance

The source directory is scanned first; the later project test scan skips that
already visited directory. Empty overlays return the existing sorted result.
There is no discovery cache, public API change, or generated-code change.

## Measurement

Production baseline: `aa3efa7296e8b02f1ca1aa26a144debcd69dc7d8`.
Code candidate: `843ebec52848f4f701135a2165a9f5a2d78d9174`, based on
`7f5834b2129b02e3c7cc1597514f8e34e04b1006`. Intervening #659/#660
do not change the discovery functions. Measurements used the baseline plus the
candidate discovery implementation, before that rebase.

Linux 6.18.55 amd64, AMD EPYC 9V74, five visible CPUs, four-CPU cgroup quota,
16 GiB memory limit, pinned Go 1.25.1. Six samples, `-cpu=1`, warm filesystem:

```sh
toolchain/go/bin/go test ./pkg/project -run '^$' \
  -bench '^BenchmarkDiscoverModules$' -benchmem -benchtime=150ms -count=6 -cpu=1
```

The fixture has N source modules, N source tests, N external tests, and excluded
hidden/vendor directories. Values below are sample medians.

| N / mode | Before | After | Allocated before / after |
| --- | ---: | ---: | ---: |
| 128 / empty overlay | 541.866 us | 304.340 us | 183,992 / 116,813 B |
| 256 / empty overlay | 1.077077 ms | 0.621149 ms | 366,946 / 232,819 B |
| 512 / empty overlay | 2.199715 ms | 1.280949 ms | 732,651 / 464,590 B |
| 512 / explicit overlays | 2.338639 ms | 1.697654 ms | 773,671 / 560,220 B |
| 512 / direct source discovery | 1.873382 ms | 1.302969 ms | 678,041 / 464,591 B |
| 512 / direct tests-only control | 1.157526 ms | 1.215681 ms | 455,470 / 455,470 B |

Empty-overlay discovery improves 42–44%; direct source scans isolate a 30–33%
traversal gain. Direct tests-only allocations are unchanged, with median timings
varying -2% to +5% across sizes. Both versions scale approximately linearly.

The accompanying compiler/frontend pipeline and CLI check/lint benchmarks do
not establish a meaningful total-pipeline speedup. Warm microbenchmarks do not
establish cold-disk performance. Discovery has no filesystem snapshot guarantee;
removing a repeated traversal can observe concurrent mutations at different times.

## Validation

- Exact code-head independent gpt-6.1-sol review: no findings; all
  `pkg/project` tests passed independently.
- Explicit ordinary, root, hidden, vendor and node_modules source directories;
  tests-only/full scans; nil/empty/nonempty overlays; sorted/deduplicated results;
  file sources, directory symlinks, missing/unreadable trees are covered.
- Integration tests passed with `-count=1` for `pkg/project`, `pkg/frontend`,
  `pkg/compiler`, `pkg/build` and `internal/cli`.
- Integration `make repo-check`, scoped `go vet` and `make dist-check` passed.
  The Linux amd64 packaged CLI exercised native builds, source tools, LSP,
  terminal/DAP debugging and profiles without host Go, dlv or downloads.
- Integration validation used the initial baseline plus the three package
  candidates. Final branch-head review and required CI gate publication/merge;
  these notes do not claim that pending remote CI has passed.

