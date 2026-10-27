# CSV parse against Rust

`@std/csv` `parse` against the Rust `csv` crate on 5000 generated rows, best of 200 parses, each materializing every cell as an owned string. Two shapes: `quoted` (quoted and escaped cells) and `plain` (no quotes).

```sh
MS=./target/release/ms sh bench/perf/csv/run.sh
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
