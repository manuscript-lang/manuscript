# Perf bash, 2026-11-18: text and data processing

Base `main` `121cf809`, Release `ms` from `make build`, 4 vCPU shared Linux VM. Probes are scratch programs (not committed), Manuscript and Rust (`rustc -O -C overflow-checks=on`, std only) or Go (`encoding/json`, `encoding/csv`, `regexp`) with the same algorithm and checksums; ms, medians of 3 where noted, otherwise one run. `ms run` builds Debug by default: time `ms build` (Release) binaries.

## Where Manuscript stands

| Probe (size) | Manuscript | Reference |
| --- | ---: | ---: |
| build 1M lines with a builder / `lines`+`split`+`parse_int` / `parse_float`+`to_fixed` | 97 / 73 / 112 | Rust 165 / 99 / 325 |
| `count`, `index_of`, `replace` over 28 MB | 41 | Rust 147 |
| upper, lower, scalar length, reverse over 11 MB mixed Unicode | 507 | Rust 599 |
| 3M Int `to_string`; 1M Float `to_string`+`to_fixed`+f-string | 37 / 180 | Rust 53 / 411 |
| word frequency, 2M words; sort 2M strings (clone included) | 112 / 147 | Rust 122 / 170 |
| read 45 MB of stdin lines, split, parse (stream) | 110 | Rust 183 |
| print 2M lines through a pipe | 110 | Rust and Go 1,650 (line buffered) |
| JSON, 33 MB: ndjson parse / array parse / parse+stringify | 342 / 510 / 352 | Go 1,134 / 776 / 1,295 |
| CSV, 500k rows with quotes and newlines: parse / stringify | 87 / 55 | Go 128 / 102 |
| Regex over 400k log lines (13 patterns: anchored, alternation, `(?i)`, `\p{L}`, lazy, replace, split) | 4 to 378 | Go 14 to 1,938, each 2.5x to 10x slower |
| TOML 2.9 MB / XML 4.8 MB / HTML 2.8 MB / YAML 7.6 MB parse | 107 / 151 / 197 / 336 | none |

No gap against Rust or Go in the table, so none of it is changed. YAML is the slowest parser at about 23 MB/s (`classify` and per-line copies, spread flat in the profile); left alone, no baseline to name a gap.

## Change: `equal_fold` compares ASCII without building keys

It built `replace().upper().lower()` for both sides before comparing. While both texts are ASCII it now compares byte by byte with ASCII lowercasing and stops at the first difference; a non-ASCII byte on either side uses the full mapping as before. A longer side is unequal because no case mapping erases a scalar.

| 166k lines, 11 MB, compared with a 9-byte text | before | after |
| --- | ---: | ---: |
| mostly ASCII lines with some non-ASCII (ms) | 105 to 144 | 18 to 26 |
| ASCII only (ms) | 22 to 28 | 9 to 13 |

## Change: `normalize` copies ASCII runs

Any non-ASCII byte sent the whole text through the per-char normalizer after a `Vec<char>` copy. ASCII never composes with what precedes it and is stable under every form, so only the last ASCII byte before a non-ASCII run through the next ASCII byte is normalized; the rest is copied.

| 11 MB of lines with 15% non-ASCII words, NFC and NFD (ms, 3 runs) | before | after |
| --- | ---: | ---: |
| `normalize` | 497, 569, 602 | 95, 102, 80 |

## Change: `title` on ASCII text

ASCII text lowercases once and copies runs between the first letters of words. Text with any non-ASCII scalar still takes the per-word path (432 to 620 ms on the mixed 11 MB probe, unchanged); a per-word ASCII path for mixed text is not done.

Not changed: `fields_by` and `map_chars` cost one closure call per scalar (116 and 64 ms for 11M scalars, no Rust twin measured); a fix is cross-function inlining of the callback, a compiler change.
