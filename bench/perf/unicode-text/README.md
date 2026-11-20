# Unicode text: case mapping and normalization

`ms run bench/perf/unicode-text/main.ms -- 100` runs `upper`, `lower` and the four normalization forms over five 64 KiB texts (ASCII, Latin with accents, Greek, CJK and Hangul, text with combining marks). Each line prints ns per 100 input bytes and a checksum of the result lengths, which must match between builds.

## 2026-11-20: Rust runtime against the C tables

Base `6d566840` (Rust, `unicode-normalization` crate and std case mapping) against the same tree with the C tables and natives. Linux x86_64 shared VM, one run of 100 passes, so treat differences under 20% as noise. All checksums are equal.

| text | upper | lower | NFC | NFD | NFKC | NFKD |
| --- | --- | --- | --- | --- | --- | --- |
| ascii | 16 → 4 | 8 → 3 | 4 → 3 | 4 → 3 | 4 → 3 | 4 → 4 |
| latin | 930 → 606 | 823 → 607 | 1787 → 106 | 1208 → 1552 | 1358 → 156 | 1155 → 1640 |
| greek | 2412 → 544 | 908 → 398 | 1559 → 258 | 1140 → 802 | 1490 → 259 | 1147 → 804 |
| cjk | 986 → 328 | 881 → 284 | 1263 → 206 | 1044 → 752 | 1298 → 739 | 1070 → 773 |
| marks | 627 → 508 | 528 → 512 | 909 → 872 | 778 → 106 | 918 → 865 | 810 → 106 |

Follow-up, same day: ASCII runs are written in one piece and scalars are encoded in place. Latin NFD 1552 → 684 and NFKD 1640 → 690 (faster than the Rust 1208 and 1155); Greek NFD 802 → 665; CJK NFD 752 → 576. The other cases are within noise.
