# Native fallbacks against Manuscript twins, 2026-11-12

Which runtime entry points exist for speed rather than as primitives, how far behind a Manuscript twin is, and which compiler capability is missing. `gaps.ms` runs each native call and a `.ms` twin on the same input and prints microseconds (min of 5) and a checksum.

```sh
ms build bench/perf/native-fallbacks/gaps.ms -o /tmp/gaps && /tmp/gaps
```

Linux x86-64, Release LLVM `ms`, 4 vCPU shared VM; compare only runs from one machine.

## Inventory

About 500 `msrt_*` symbols are exported from `ms-rt` (string 62, list 43, bytes 24, map 23, promise 18, bits 14, set 10); 27 more live in `ms-rt-hot` and are inlined. Most are real primitives (allocation, tasks, I/O, faults, promises, clocks). The ones that exist for speed:

| area | entry points | measured |
| --- | --- | --- |
| scan and compare | `msrt_bytes_index_of*`, `msrt_string_find`/`index_of_long`/`contains_long`/`count`, `ms-rt-hot` `bytes_eq`/`equal`/`memchr_short`/`find_*` | yes |
| checksums | `msstd_checksum_crc32`/`adler32` (SIMD CRC-32) | yes |
| sorting | `msrt_list_sort_*`, `msrt_list_sorted*` (`sortgen` inlines a known comparator) | yes |
| maps and sets | `msrt_map_*`, `msrt_set_*`, `ms-rt-hot` probes and hashes | yes (counting loop) |
| text | `split`, `lines`, `chars`, `trim`, `replace`, `upper`, `lower`, `repeat`, `pad_*`, `msrt_string_fmt*` | no (blocked on builders) |
| bytes builders | `BytesBuilder`, `StringBuilder`, `msrt_bytes_concat`/`append`/`slice`, `msrt_list_extend`/`concat`/`slice` | no (no `.ms` buffer with an inline store) |
| inflate | `ms-inflate` (898 lines, used by HTTP, archive and streams), `msstd_compress_*` | no |
| codecs | base64, base32, ascii85, `msstd_json_*`, HTML escape | no |

Scratch buffers are read buffers in `ms-std-fs` and `ms-std-net`; they hold I/O state, not a speed fallback.

## Gap (Manuscript twin against native)

| case | native us | twin us | twin / native |
| --- | ---: | ---: | ---: |
| `index_of_byte`, 1 MB, byte loop | 12 | 347 | 29x |
| same, 32-byte blocks (after this change) | 12 | 31 | 2.6x |
| same, 8 bytes at a time through `int64_le` | 12 | 172 (903 before the inline load) | 14x |
| `==` of two 1 MB strings, byte loop (x20) | 765 | 7,425 | 9.7x |
| same, 32-byte blocks (after this change) | 765 | 732 | 0.96x |
| same, through `int64_le` | 765 | 4,916 (36,834 before the inline load) | 6.4x |
| `index_of` of a 7-byte absent needle in 1 MB | 53 | 1,418 | 27x |
| `crc32` of 1 MB, table loop | 524 | 5,211 | 9.9x |
| sort 1M `Int`, merge sort | 20,205 | 178,424 | 8.8x |
| count 1M keys into 100k `Int`s | 49,066 (`Map`) | 14,082 (flat table, fixed size) | 0.29x |

The flat table has no growth and no deletion, so its win bounds what a `Map[Int, Int]` specialization can reach, not what it will.

## Causes

1. **A fixed-size block of reads was checked.** `a[i + j]` under `i + 32 <= len` and `j < 32` kept its bounds check, because the relation was recorded on `i + 32`, not on `i`. A checked read has two exits, so LLVM cannot vectorize the block. The range pass now derives `x <= b - c` from `x + c <= b` (`prove_le`); the block loops are unchecked and vectorize (memchr 730 to 31 us, equality 1,027 to 36 us per scan, native 12 and 44).
2. **No inline word load.** `Bytes.int64_le` called `msrt_bytes_read_word` in the archive, so a SWAR scan cost a call per word and was slower than the byte loop. The function now lives in `ms-rt-hot` (its status return is an `i64`, matching the declaration generated code makes, which is what lets LLVM inline it), and a read with a constant width is one compare and one load: SWAR memchr 903 to 172 us, SWAR equality 36,834 to 4,916 us. Every `int16`/`int32`/`int64`/`uint*` reader in `@std/bytes.ms` gets the same gain (binary formats, codecs, hashing, UTF-8 validation).
3. **No bulk store.** A `.ms` twin cannot produce bytes without `BytesBuilder` or a per-element `append`, so every copying primitive stays native until a buffer has an inline unchecked store after one reserve.
4. **No SIMD below the block pattern.** Native `memchr` uses wider vectors than the baseline `x86-64` target gives LLVM (2.6x left), and CRC-32 uses carry-less multiply (9.9x for table code). These two stay native: `memchr`, `memcmp`, `memcpy` and CRC are libc-sized primitives.
5. **No specialization of `Map`/`Set` per key type.** The runtime derives slot layout from descriptors on each call; a flat table indexed by the key's hash is 3.5x faster in the counting loop.
6. **Sort needs preconditions the checker cannot see.** The twin's `a[j + 1]` and `tmp[k]` keep their checks (`hi` is a parameter unrelated to `len`), and it copies back each merge; this twin is not a fair bound, and the native sort stays with `sortgen` for comparator inlining.

## Plan, in order

1. Window relation in the range pass (this change). Unlocks vectorized byte loops in `.ms`; next, move `bytes_eq`/`memcmp`-style equality and short-needle scans onto it and delete the Rust twin where the instruction count matches.
2. Inline fixed-width loads (done in this branch). Left: the `Result` wrapper still builds an error on the cold path in each caller.
3. A byte buffer type with an inline store, so copy, concat, slice, `BytesBuilder` and the codecs can be `.ms`.
4. `Map`/`Set` specialization per key type in `.ms`, starting with `Int` and `String` keys.
5. Inflate and base64 in `.ms` after 2 and 3; measure on `bench/perf/codecs` before deleting the Rust.
6. Keep native: `memchr`/`memmem` over long input, `memcpy`, SIMD CRC, allocation, tasks and I/O.
