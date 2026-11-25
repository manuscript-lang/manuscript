# CSV parse and write against Rust

`@std/csv` `parse` and `stringify` against the Rust `csv` crate on 5000 generated rows, best of 200 parses, each materializing every cell as an owned string. Two shapes: `quoted` (quoted and escaped cells) and `plain` (no quotes).

```sh
MS=./target/release/ms ms run bench/perf/tools/cargo_vs_ms.ms -- csv
```

Compare numbers only from the same machine.

## 2026-10-27, Linux amd64, 4 cores, after #1659

| Shape | Manuscript | Rust csv |
| --- | --- | --- |
| quoted | 985 µs | 796 µs |
| plain | 515 µs | 974 µs |

An earlier run of the same programs gave quoted 887 µs against 943 µs, so on quoted input the two are within run-to-run noise; Rust is ahead on that shape in this run. Plain input is about twice as fast in Manuscript.

Before #1659 `parse` built a `List[Int]` of scalars per line; the same quoted shape took about 1.3 ms per parse in the stdlib micro-benchmark.

## 2026-10-27, Linux amd64, 4 cores, after the byte-scan parser

Three runs each; ranges are best-of-200 per run.

| Shape | Manuscript | Rust csv |
| --- | --- | --- |
| quoted | 785-832 µs | 804-911 µs |
| plain | 476-535 µs | 974-1212 µs |

`parse` scans the input once as `Bytes` with `index_of_byte` and decodes each cell with `decode_utf8_range`; lines without quotes still take one native `split`.

## 2026-11-15, Linux amd64, 4 cores, `stringify` without per-row strings

The programs also time `stringify` (`quoted-write`, `plain-write`: the parsed rows written back, best of 200). `stringify` built, per row, a list of encoded cells, a joined line and a second interpolated line before appending it, so every row allocated and copied its text three times. It now appends each cell and delimiter straight into the output builder and counts bytes as it goes; the output and the budget errors are unchanged.

Built with `ms build` (Release) before and after the change, three runs each, best of 200 per run:

| Shape | Before | After | Rust csv |
| --- | --- | --- | --- |
| quoted-write | 790-797 µs | 587-613 µs | 231-297 µs |
| plain-write | 559-785 µs | 452-461 µs | 206-263 µs |

On a larger document (40000 rows of six cells, 3 MB, written from parsed rows, median of 31 runs, five alternating runs per build) the write went from 14.3-17.2 ms to 8.6-11.1 ms, about 1.6x faster. For reference on the same document and machine, the Rust `csv` writer took 5.3 ms and Go's `encoding/csv` 10-14 ms.

Manuscript is still about 2x slower than Rust on writing. The remaining cost is the four substring searches per cell in the quote check; replacing them with one loop over the cell's bytes was slower (865 µs quoted) and was dropped.

