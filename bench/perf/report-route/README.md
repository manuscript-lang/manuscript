# Program-map route queue — 2026-11-12

Baseline: `37a14ba5797bed73a66d1350bee03d2238c63a20`. Candidate is this directory's commit. Run `node bench/perf/report-route/run.cjs <baseline>` from this checkout; it extracts the production route functions from Git and the working tree. No compiler, browser, DOM, or network is used.

On Linux x64, Node v24.19.0, Intel Xeon Platinum 8573C: 11 alternating samples after three warmup pairs. Synthetic fan-out graphs retain the same shortest-route HTML, asserted before timing; a checksum consumes results. At 100 branches, median 0.0322 ms becomes 0.0252 ms; 10,000: 2.158 to 1.365 ms; 20,000: 33.816 to 3.457 ms; 40,000: 141.690 to 7.941 ms. Raw samples and machine details are in `results-2026-11-12.json`.

An advancing queue index removes repeated front removal while keeping breadth-first discovery and tie order. These are actual pure-function measurements, not browser responsiveness or CLI timings. The wide graph is a stress case. Shared-host timings are not an SLA. The behavioral tests also cover cycles, duplicate edges, same-entity routes, unreachable targets, escaped labels and reaching the last wide branch.
