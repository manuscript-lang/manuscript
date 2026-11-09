# URL parent-reference resolution

Measures the native URL path helper with repeated parent segments and ordinary relative-path controls. Build and input construction are outside the timer; each result is checked before its length contributes to the checksum.

```sh
rustc --edition=2024 -O bench/perf/url-parents/main.rs -o /tmp/url-parents
/tmp/url-parents 8000 10 parents
/tmp/url-parents 1 100000 parents
/tmp/url-parents 4 100000 parents
/tmp/url-parents 0 100000 plain
/tmp/url-parents 0 100000 normal
```

Run matching baseline and candidate binaries in alternating order, pinned to one CPU where supported. Compare medians over at least nine pairs; use 1000, 2000, 4000 and 8000 parent segments to check scaling. The Rust helper benchmark isolates path resolution, not complete Manuscript invocation or HTTP processing. No network is used.
