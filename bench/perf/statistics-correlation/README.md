# Correlation accuracy guard cost

Paired measurements for the `statistics.correlation` and `linear_regression` change in PR #3468 (large-offset correlation, issue #3467). `main.ms` runs each case in one process and prints nanoseconds per call and the result; the cases are ordinary data, constant data, narrow spread, tiny and large magnitudes, a large common offset, and three short epoch-second controls (`ts-same`, `ts-reversed`, `ts-line`, `1e9 + i` for i in 0..9) whose plain result is already exact.

## Revisions and machine

- Before: compiler, runtime and stdlib from `451995a1c` (main) plus the unrelated parser/formatter commits of the #3476 branch (`ec8ad9956`); `stdlib/math/statistics.ms` is unchanged there.
- After: `517041a67`, the #3468 branch merged with the same main.
- Both built with `ms build ... --build-type Release`, once with the default LLVM backend and once with `MS_BACKEND=cranelift`; the `ms` binaries are the debug `target/debug/ms` of each revision.
- Intel Xeon @ 2.10GHz, 4 vCPU virtual machine, Linux 6.18; each process pinned with `taskset -c 1`. Shared host: expect noise of several percent.

## Reproduce

```sh
cd bench/perf/statistics-correlation
ms build main.ms --build-type Release -o before-llvm                  # with the before compiler
ms build main.ms --build-type Release -o after-llvm                   # with the after compiler
MS_BACKEND=cranelift ms build main.ms --build-type Release -o before-cranelift
MS_BACKEND=cranelift ms build main.ms --build-type Release -o after-cranelift
./run.sh 20                    # 20 alternating AB/BA pairs per backend into raw/
python3 summarize.py 20        # medians, pairs-slower counts, result changes
```

`raw-samples.json` holds every output line of the 2026-11-10 run, keyed by backend, side and pair; `summarize.py` reads `raw/` files with the same layout.

## Findings (2026-11-10, 20 pairs)

- Inputs whose plain result lost the spread (`offset-1e16`): 3.5x to 4.6x slower in all 20 pairs on both backends, and the result changes from 0.68 or 0.63 to the correct 1.
- Short epoch-second controls (`ts-*`, n = 10): the correlation guard sends them to the fallback although the plain result was already exact (1, -1, 1). They are 3.0x to 5.0x slower in 20 of 20 pairs on both backends (about 400 to 700 ns absolute) with identical results. This is the accuracy-for-time tradeoff of the 2^-48 floor, not noise.
- Ordinary, constant and narrow-spread data at n = 1000: LLVM ratios 0.99 to 1.23 with 8 to 16 of 20 pairs slower (the largest are `tiny` correlation 1.23 and `const-both` regression 1.15, not repeated here); Cranelift 0.82 to 1.04.
- Ordinary data at n = 10: LLVM correlation 0.84 to 1.12 and regression 0.82 to 1.15. Cranelift is consistently slower, correlation 1.12 to 1.36x and regression 1.06 to 1.46x (15 to 19 of 20 pairs slower, 15 to 25 ns absolute); this small-n Cranelift cost is not explained or fixed here.
- `timestamps` at n = 1000 (varying data, not the short exact controls): parity.

The #2966 performance hold stays with its owner until these numbers are accepted.

## Full tables


### llvm

| case | n | before median ns | after median ns | ratio | pairs slower | result before -> after |
|---|--:|--:|--:|--:|--:|---|
| corr ts-same | 10 | 159 | 570 | 3.58 | 20/20 | 1 |
| reg ts-same | 10 | 404 | 468 | 1.16 | 14/20 | 1 |
| corr ts-reversed | 10 | 160 | 586 | 3.66 | 20/20 | -1 |
| reg ts-reversed | 10 | 446 | 454 | 1.02 | 11/20 | 2000000008 |
| corr ts-line | 10 | 194 | 584 | 3.01 | 20/20 | 1 |
| reg ts-line | 10 | 534 | 435 | 0.81 | 11/20 | -1999999997 |
| corr broad-perfect | 10 | 198 | 166 | 0.84 | 8/20 | 1 |
| reg broad-perfect | 10 | 42 | 34 | 0.82 | 5/20 | 3 |
| corr broad-centered | 10 | 197 | 180 | 0.91 | 10/20 | 0.5303144222972894 |
| reg broad-centered | 10 | 35 | 32 | 0.91 | 7/20 | 2.636363636364201 |
| corr broad-noisy | 10 | 185 | 160 | 0.86 | 8/20 | 0.5303144222972894 |
| reg broad-noisy | 10 | 37 | 32 | 0.86 | 9/20 | 3.363636363635446 |
| corr orthogonal | 10 | 170 | 183 | 1.08 | 9/20 | 0 |
| reg orthogonal | 10 | 38 | 34 | 0.88 | 6/20 | 0.19999999999987284 |
| corr const-x | 10 | 164 | 166 | 1.01 | 9/20 | 0 |
| reg const-x | 10 | 400 | 422 | 1.05 | 11/20 | 0 |
| corr const-y | 10 | 166 | 182 | 1.10 | 12/20 | 0 |
| reg const-y | 10 | 34 | 32 | 0.96 | 6/20 | 3 |
| corr const-both | 10 | 136 | 134 | 0.99 | 11/20 | 0 |
| reg const-both | 10 | 392 | 417 | 1.07 | 11/20 | 0 |
| corr price-narrow | 10 | 152 | 170 | 1.12 | 12/20 | 0.5303144222973336 |
| reg price-narrow | 10 | 407 | 468 | 1.15 | 14/20 | -18.92060606061979 |
| corr timestamps | 10 | 152 | 530 | 3.47 | 20/20 | 1 |
| reg timestamps | 10 | 416 | 424 | 1.02 | 14/20 | -999999999 |
| corr offset-1e16 | 10 | 168 | 613 | 3.66 | 20/20 | 0.6782329983132448 -> 1 |
| reg offset-1e16 | 10 | 408 | 453 | 1.11 | 15/20 | -5000000000000000 |
| corr tiny | 10 | 161 | 160 | 0.99 | 13/20 | 0.5303144222972894 |
| reg tiny | 10 | 416 | 438 | 1.05 | 14/20 | 0.696969696969171 |
| corr large | 10 | 161 | 162 | 1.01 | 12/20 | 0.5303144222972894 |
| reg large | 10 | 434 | 422 | 0.97 | 13/20 | 2.6666666666670705e+200 |
| corr broad-perfect | 1000 | 15907 | 16184 | 1.02 | 13/20 | 0.9999999999999999 |
| reg broad-perfect | 1000 | 2313 | 2431 | 1.05 | 13/20 | 3 |
| corr broad-centered | 1000 | 15164 | 16462 | 1.09 | 12/20 | 0.0038776934669337176 |
| reg broad-centered | 1000 | 2403 | 2396 | 1.00 | 13/20 | 0.0030302360211547303 |
| corr broad-noisy | 1000 | 15960 | 16740 | 1.05 | 12/20 | 0.003877693466933717 |
| reg broad-noisy | 1000 | 2350 | 2342 | 1.00 | 9/20 | 6.976319046804296 |
| corr orthogonal | 1000 | 15852 | 17228 | 1.09 | 11/20 | 0 |
| reg orthogonal | 1000 | 2336 | 2490 | 1.07 | 13/20 | 0 |
| corr const-x | 1000 | 15234 | 15966 | 1.05 | 10/20 | 0 |
| reg const-x | 1000 | 37796 | 38684 | 1.02 | 12/20 | 0 |
| corr const-y | 1000 | 16038 | 15815 | 0.99 | 11/20 | 0 |
| reg const-y | 1000 | 2424 | 2376 | 0.98 | 12/20 | 3 |
| corr const-both | 1000 | 12688 | 12668 | 1.00 | 11/20 | 0 |
| reg const-both | 1000 | 39644 | 45647 | 1.15 | 15/20 | 0 |
| corr price-narrow | 1000 | 16098 | 17221 | 1.07 | 11/20 | 0.003877693466933123 |
| reg price-narrow | 1000 | 41412 | 39393 | 0.95 | 13/20 | 49.766177541875784 |
| corr timestamps | 1000 | 15706 | 15552 | 0.99 | 8/20 | 0.009588652335259603 |
| reg timestamps | 1000 | 39390 | 37394 | 0.95 | 15/20 | -162454.26444955132 |
| corr offset-1e16 | 1000 | 15902 | 55114 | 3.47 | 20/20 | 0.6329296959378621 -> 0.9999999999999999 |
| reg offset-1e16 | 1000 | 37008 | 45279 | 1.22 | 15/20 | -5000000000000000 |
| corr tiny | 1000 | 15189 | 18741 | 1.23 | 13/20 | 0.0038776934669337176 |
| reg tiny | 1000 | 38176 | 42243 | 1.11 | 16/20 | 0.002967909912982149 |
| corr large | 1000 | 16129 | 16264 | 1.01 | 15/20 | 0.00387769346693372 |
| reg large | 1000 | 42502 | 41430 | 0.97 | 13/20 | 6.973351136891396e+200 |

### cranelift

| case | n | before median ns | after median ns | ratio | pairs slower | result before -> after |
|---|--:|--:|--:|--:|--:|---|
| corr ts-same | 10 | 224 | 889 | 3.97 | 20/20 | 1 |
| reg ts-same | 10 | 556 | 736 | 1.32 | 18/20 | 1 |
| corr ts-reversed | 10 | 189 | 918 | 4.85 | 20/20 | -1 |
| reg ts-reversed | 10 | 493 | 652 | 1.32 | 18/20 | 2000000008 |
| corr ts-line | 10 | 186 | 935 | 5.03 | 20/20 | 1 |
| reg ts-line | 10 | 486 | 648 | 1.34 | 18/20 | -1999999997 |
| corr broad-perfect | 10 | 184 | 242 | 1.32 | 17/20 | 1 |
| reg broad-perfect | 10 | 33 | 48 | 1.44 | 19/20 | 3 |
| corr broad-centered | 10 | 187 | 252 | 1.35 | 17/20 | 0.5303144222972894 |
| reg broad-centered | 10 | 32 | 39 | 1.22 | 15/20 | 2.636363636364201 |
| corr broad-noisy | 10 | 202 | 236 | 1.17 | 16/20 | 0.5303144222972894 |
| reg broad-noisy | 10 | 34 | 39 | 1.15 | 17/20 | 3.363636363635446 |
| corr orthogonal | 10 | 198 | 269 | 1.36 | 19/20 | 0 |
| reg orthogonal | 10 | 34 | 49 | 1.46 | 15/20 | 0.19999999999987284 |
| corr const-x | 10 | 190 | 255 | 1.34 | 17/20 | 0 |
| reg const-x | 10 | 496 | 602 | 1.21 | 17/20 | 0 |
| corr const-y | 10 | 202 | 226 | 1.12 | 14/20 | 0 |
| reg const-y | 10 | 34 | 36 | 1.06 | 14/20 | 3 |
| corr const-both | 10 | 149 | 172 | 1.15 | 17/20 | 0 |
| reg const-both | 10 | 500 | 592 | 1.18 | 16/20 | 0 |
| corr price-narrow | 10 | 199 | 250 | 1.25 | 14/20 | 0.5303144222973336 |
| reg price-narrow | 10 | 494 | 704 | 1.42 | 16/20 | -18.92060606061979 |
| corr timestamps | 10 | 196 | 831 | 4.23 | 20/20 | 1 |
| reg timestamps | 10 | 496 | 637 | 1.29 | 14/20 | -999999999 |
| corr offset-1e16 | 10 | 212 | 984 | 4.64 | 20/20 | 0.6782329983132448 -> 1 |
| reg offset-1e16 | 10 | 626 | 651 | 1.04 | 15/20 | -5000000000000000 |
| corr tiny | 10 | 224 | 252 | 1.12 | 15/20 | 0.5303144222972894 |
| reg tiny | 10 | 640 | 702 | 1.10 | 16/20 | 0.696969696969171 |
| corr large | 10 | 258 | 295 | 1.15 | 16/20 | 0.5303144222972894 |
| reg large | 10 | 679 | 648 | 0.96 | 15/20 | 2.6666666666670705e+200 |
| corr broad-perfect | 1000 | 22282 | 18890 | 0.85 | 16/20 | 0.9999999999999999 |
| reg broad-perfect | 1000 | 2506 | 2392 | 0.95 | 8/20 | 3 |
| corr broad-centered | 1000 | 21293 | 19011 | 0.89 | 15/20 | 0.0038776934669337176 |
| reg broad-centered | 1000 | 2683 | 2311 | 0.86 | 7/20 | 0.0030302360211547303 |
| corr broad-noisy | 1000 | 19316 | 18692 | 0.97 | 14/20 | 0.003877693466933717 |
| reg broad-noisy | 1000 | 2578 | 2372 | 0.92 | 10/20 | 6.976319046804296 |
| corr orthogonal | 1000 | 22208 | 18305 | 0.82 | 12/20 | 0 |
| reg orthogonal | 1000 | 2804 | 2336 | 0.83 | 9/20 | 0 |
| corr const-x | 1000 | 21422 | 18996 | 0.89 | 11/20 | 0 |
| reg const-x | 1000 | 61060 | 55021 | 0.90 | 12/20 | 0 |
| corr const-y | 1000 | 17928 | 18664 | 1.04 | 16/20 | 0 |
| reg const-y | 1000 | 2407 | 2319 | 0.96 | 10/20 | 3 |
| corr const-both | 1000 | 15502 | 14082 | 0.91 | 12/20 | 0 |
| reg const-both | 1000 | 57277 | 56399 | 0.98 | 13/20 | 0 |
| corr price-narrow | 1000 | 20600 | 18501 | 0.90 | 12/20 | 0.003877693466933123 |
| reg price-narrow | 1000 | 58955 | 56363 | 0.96 | 13/20 | 49.766177541875784 |
| corr timestamps | 1000 | 20885 | 18648 | 0.89 | 12/20 | 0.009588652335259603 |
| reg timestamps | 1000 | 60804 | 55466 | 0.91 | 13/20 | -162454.26444955132 |
| corr offset-1e16 | 1000 | 19496 | 75508 | 3.87 | 20/20 | 0.6329296959378621 -> 0.9999999999999999 |
| reg offset-1e16 | 1000 | 54322 | 56895 | 1.05 | 15/20 | -5000000000000000 |
| corr tiny | 1000 | 18025 | 18784 | 1.04 | 15/20 | 0.0038776934669337176 |
| reg tiny | 1000 | 57033 | 55618 | 0.98 | 15/20 | 0.002967909912982149 |
| corr large | 1000 | 20510 | 18971 | 0.92 | 13/20 | 0.00387769346693372 |
| reg large | 1000 | 60046 | 56426 | 0.94 | 14/20 | 6.973351136891396e+200 |


## 2026-11-10 (second attempt): a cheaper exactness guard for correlation (#3467, #3482)

The first attempt (#3468, reverted) sent short epoch-second series through the compensated fallback. The guard is now
`xx > mean_x^2 * 2^-75 * n^3` for each list (the mean square deviation clears `2^-75 * n^2` of the squared mean), checked
inline after the plain sums with no extra calls. Accuracy argument, in `CORRELATION_FLOOR`'s comment: a rounded mean shifts every
deviation by one error d, which changes the correlation only at second order, by about `(n*d)^2 / (n*sx*sy)`, so the error is near
`2^-106 / 2^-75 = 2^-31` at the floor. Checked against exact rational arithmetic: 4000 random samples (worst error 2.9e-11 when
accepted, up to 0.5 when rejected) and 4652 adversarial samples within a decade above the floor (worst 5.7e-11); 409 inputs through the
real function (offsets 0 to 1e15, 2 to 200 points, plus nonfinite, constant, tiny, huge, empty and single-value cases): the largest error
fell from 7.7e-2 to 3.9e-13, no input got worse, and every edge case returned the same value as before.

Paired build and runs as above (24 alternating pairs per backend, same `main.ms`; before is main `ae87aceda`, after is the working tree; debug `ms` builds):

- LLVM: correlation on every ordinary, constant, narrow, tiny/large and timestamp control stays within 0.85 to 1.12x (median 1.00); regression, whose code is unchanged, ranges 0.81 to 1.15x (median 1.00). `corr ts-same n=10`: 231 -> 238 (1.03x).
- Cranelift: correlation controls 0.96 to 1.25x (median 1.08), but regression, whose code path is unchanged, shows 0.96 to 1.26x (median 1.07) in the same run, so most of that offset is not this change. An A/A-style control (main plus one unused function, same compiler) gave a median ratio of 1.01 on Cranelift (max 1.31) and 1.07 on LLVM (max 1.5): run-to-run noise on this shared host is several percent.
- `offset-1e16` (correlation, n=10 / 1000): 245 -> 766 (3.12x) / 17192 -> 68445 (3.98x) on LLVM: slower by design, and now correct.

Not claimed: instruction counts, other machines, an explanation of the residual Cranelift offset.
