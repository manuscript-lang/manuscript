# TOML parse against Rust

`@std/toml` `parse` against the Rust `toml` crate (`toml::Table`, 0.9 and 0.8) on the document the stdlib benchmark generates: 2000 tables of an integer, a string and a two-element array, 110,670 bytes. Best of 200 parses.

```sh
MS=./target/release/ms ms run bench/tools/cargo_vs_ms.ms -- toml
```

Compare numbers only from the same machine.

## 2026-10-27, Linux amd64, 4 cores, main at 9f41921f

| Parser | Best parse |
| --- | ---: |
| Manuscript `@std/toml` | 3.04-3.14 ms |
| Rust `toml` 0.9.12 | 3.58-3.73 ms |
| Rust `toml` 0.8 | 5.62-5.95 ms |

Manuscript is 0.85x the time of `toml` 0.9 and 0.54x that of 0.8. The reader has scanned `Bytes` since #1658, which closed the ~1.2x gap recorded in #1675.
