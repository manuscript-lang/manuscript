# Final main replay rejects the TOML helper, 2026-10-31

The helper optimization in #2093 was acceptable on its initial controls, but
main `09e0eb7e66b0437d257dd5e2702855a158c35739` exposes a reproducible common-path
regression. Restore the original radix/padding helper. Output and public behavior
remain identical. The revert gives up the measured dense-control gain.

## Matched evidence

Both producers use the exact same main 09e0 compiler/native sources, toolchain,
release settings, inputs and native archive. Only the source TOML helper differs.
The original helper's full file is byte-identical to the historical source at
`3cfde58b6`; the merged helper is main 09e0's file. The benchmark runner's
`revision` / `base_commit` names 3cf solely to validate that original TOML file;
**09e0 is the actual integration base**, recorded as `integration_base` and in
both native-source records. Those native source, manifest, root lock and license
hashes match main 09e0. The temporary build-file restoration method and original
workspace guard hashes are explained in the environment annotation.

No JSON candidate code is in either producer. This isolates the decision from
separate JSON conversion work. No backend or layout cause is asserted or
investigated. main 98854115f contains no intervening TOML, JSON-native, runtime or
root-lock changes; later merged-main replay remains necessary.

The [full matrix](results/2026-10-31/final-main/full/summary.json) repeats all eight
controls with twelve balanced interleaved trials. Whole outputs decode to the
same single-string TOML table and before/after Manuscript bytes are identical.
Labels retain the experiment's chronology: `before` is the original helper,
`after` is the helper being reverted. The source tests also pass with the original.

The [long A/A confirmation](results/2026-10-31/final-main/focused/summary.json)
uses two labels for the same original binary, plus the merged helper, about 700ms
per baseline process, twelve trials and all six orders twice:

| Workload | Original A ns | Original B ns | Merged helper ns | Merged/A |
| --- | ---: | ---: | ---: | ---: |
| common | 485.4 | 487.0 | 520.3 | 1.072× |
| ascii-16k | 73847.3 | 73648.8 | 82799.4 | 1.121× |
| sparse-escape | 73539.2 | 73404.7 | 82920.1 | 1.128× |
| dense-escape | 178538.0 | 179180.6 | 123453.0 | 0.691× |

Common, long ASCII and sparse ranges do not overlap the original ranges.
Identical-baseline medians are within 0.4%, while merged-helper common paths are
about 7–13% slower. Dense controls are about 1.45× faster with the merged helper;
that gain does not justify the protected common-path cost. All negative and
positive records remain committed; earlier successful runs are historical,
not evidence that the helper is safe on final main.

The root cause beyond the exact helper toggle remains unresolved within the
permitted campaign scope. Do not tune instruction placement or discard these
controls to recover the isolated dense win.

## Validation and replay

The full 288 and long 144 observations have complete unique case/label/trial sets,
correct counts/checksums, all balanced orders, source/binary hashes and full
semantic output checks. Independent review verifies the matched attribution and
recomputed distributions. All 14 current TOML tests, four quoting tests and 12 corpus TOML tests pass with
an immutable main09e0 compiler containing the original helper. Workspace Rust
formatting, Python syntax and whitespace checks pass. Repository checks initially
rejected raw benchmark inputs containing CR; they are now preserved as escaped
`.input.json` records with decoded-byte SHA-256, rather than weakening that rule.

[Whole-process RSS](results/2026-10-31/final-main/memory/samples.json) repeats five
large cases six times per label (90 records). Original/merged median KiB:
ASCII 4944/4940, Unicode 5712/5708, sparse 4944/4940, dense 8272/8268,
mixed 5584/5580. RSS is flat and does not overturn the timing rejection; it is
not an allocation-count claim.

Use two clean worktrees at main 09e0. Restore only `stdlib/toml.ms` to 3cf in one;
keep the merged helper in the other. In each run `cargo xtask runtime`,
`cargo build --release --locked -p ms-cli`, then the unchanged source producer
build from the original report. Use Rust 1.99.1, LLVM 23.1.1 and the same pinned
Rust TOML 0.9.8 control. The [full run driver](run.py) and [focused driver](focused.py)
reject changed bytes, semantic mismatches and invalid counts/checksums.
Use a fresh output directory and regenerated provenance from the actual builds.

```sh
python3 bench/perf/toml-quoting/focused.py --before /absolute/original --after /absolute/merged --summary /fresh/full/summary.json --output /fresh/focused
```

No new behavior test is needed for the inverse helper change: existing exact
escape, every-control, key/Unicode and budget tests cover the same contract.
Normal required CI remains enabled; no GitHub approval is submitted on the user's
behalf. Backend, ownership/cleanup, HTTP, Debug JSON and Windows investigation
remain outside this campaign's permitted scope.
