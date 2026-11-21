# Checksums and hashes

64 MB input; `main.ms` and `main.go` run the same operations. Times are milliseconds, median of 3 runs on a shared VM, 2026-11-16.

| Operation | Manuscript before | Manuscript after | Go |
| --- | --- | --- | --- |
| crc64 (ISO) | 330 | 50 | 50 |
| crc32 | 44 | 11 | 12 to 16 |
| sha512 | 160 | 160 | 91 to 159 |
| blake2b | 250 | 250 | not in the Go program |

`crc64` ran bit by bit in `src/stdlib/crypto/hash.ms`. It now builds slicing tables (one table from 256 bytes, eight from 4096) and matches Go. Outputs are unchanged (the test `CRC64 table paths equal the bitwise path` covers both polynomials and the thresholds).

`crc32` keeps slicing-by-eight as the portable path and as the oracle in its tests, and uses PCLMULQDQ folding on x86-64 (from 128 bytes) and the CRC32 instructions on AArch64 when the CPU has them (run-time detection), as Go does.
