# Perf bash, 2026-11-18: peak memory, startup and binary size

Base `main` at e36d2729, Release `ms` (LLVM), 4 vCPU shared Linux VM. Peak resident set is the child's `ru_maxrss` from `wait4` (minimum of 5 runs). Rust is `rustc -O`, standard library only. Programs are scratch workloads (not committed).

## Where Manuscript stands

| Program | Manuscript | Rust |
| --- | ---: | ---: |
| hello world: binary / RSS / start to exit | 707 KB / 2.2 MB / 1.5 ms | 4.4 MB (341 KB stripped) / 2.1 MB / 1.5 ms; C 16 KB / 1.5 MB / 1.2 ms |
| `List[Int]` 10M appends and sum, RSS | 90 MB | 80 MB |
| `List[Bool]` 20M, RSS | 24 MB | 22 MB |
| `Map[Int, Int]` 2M inserts and lookups, RSS / ms | 99 MB / 165 | 106 MB / 343 |
| 1M `String` (`item-N`), RSS | 18 MB | 57 MB |
| 5M three-field records, RSS | 121 MB | 119 MB |
| binary tree depth 22, RSS / ms | 135 MB / 152 | 264 MB / 518 |
| `Map[String, Int]` 1M inserts and lookups, RSS / ms | 68 MB / 331 | 132 MB / 929 |
| 1M three-element `List[List[Int]]`, RSS | 58 MB | 72 MB |
| `StringBuilder` 60 MB, RSS | 62 MB | 61 MB |

Startup is level with Rust, and memory is level or better everywhere except one list case, fixed below.

## Change: a list that grows out of a presized block no longer keeps the old block

The compiler presizes a list built in a loop with a known trip count (1M elements for a 3M-pass loop). That first 8 MiB block comes from the system allocator. When the list doubles, it moves into the growth region once and extends in place from then on, but `realloc` freed the old block into the large-block cache, where its 8 MiB stayed resident beside the live list. The moved block now goes straight back to the system.

| `List[Int]` built by appends | before | after | Rust |
| --- | ---: | ---: | ---: |
| 3M elements, RSS | 35.1 MB | 27.0 MB | 25.5 MB |
| 10M elements, RSS | 90.1 MB | 81.9 MB | 80.2 MB |

## Change: the error for a failed native call is built by one function, not inline at every call

A fallible native call turned a nonzero status into an `Error` with a chain of up to 16 cases (kind, message words, optional native text), copied into every call site. In the HTTP and WebSocket standard library that was 16 sites and 284 error constructions; `WebSocketSink.write` alone, three lines of source, compiled to 85 KB. Lowering now emits one function per status table (module domain, rows, whether the native has text) and each site calls it.

| `bench/perf/web/ms` server | before | after |
| --- | ---: | ---: |
| MIR lines (`ms emit`) | 12,070 | 6,414 |
| executable bytes | 3,960,976 | 3,648,696 |

The Rust hyper server is 926 KB, but it has no TLS; the Manuscript server carries rustls for `serve(tls: ...)`, about 30% of its remaining size. Output is unchanged: the conformance corpus (4,060 and 1,460 fixtures) passes.

## Change: sorting records that own data frees the merge buffer before cloning the result

`sorted` over records with a `String` field copies the list twice as raw scratch (working copy and merge buffer), sorts, then clones the working copy into the result. The merge buffer was freed last, so the sort held the original, two scratch copies and the result at once. It is now freed right after the sort, so the result reuses its block.

| 1M records of `Int`, `String`, `Float`, sorted by the float | before | after | Rust (`sort_by` in place) |
| --- | ---: | ---: | ---: |
| peak RSS | 127 MB | 96 MB | 92 MB |

Other programs measured, all level with Rust or better: 5M `Int?` list 82 vs 80 MB, `map`/`filter`/`map` over 5M ints 56 vs 54 MB, 8M floats 66 vs 65 MB, 200k-line split 23 vs 25 MB, 5M-int `sorted` 43 vs 100 MB, 1M-string `Set` 92 vs 122 MB.

## Not planned

- Hello world is 546 KB stripped against Rust's 341 KB because about 220 KB is Rust `std` backtrace, DWARF reader and unwinder code that the default panic hook keeps reachable. Removing it needs `-Zbuild-std` with `panic_immediate_abort`, which is nightly only; the repository pins stable 1.99.1.
- `sortstr` (1M strings sorted with `compare`) is 623 ms against Rust's 505 ms: a time gap in string comparison, not a memory one; left for a later round.
