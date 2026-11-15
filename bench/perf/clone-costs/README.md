# Clone costs

Where `.clone()` time goes for lists, maps and strings. Each line of `clone.ms` prints `name microseconds checksum`.

```sh
ms build --build-type Release bench/perf/clone-costs/clone.ms -o /tmp/clone && /tmp/clone
```

## 2026-11-15: Linux x86_64

Release Cranelift-built `ms` (`make build`), 4 vCPU shared VM, median of 3 runs, microseconds for the whole case.

| case | before | after |
| --- | ---: | ---: |
| `List[Int]` 1M x50 | 34,782 | unchanged (memory bound, about 10 GB/s) |
| `List[plain record]` 1M x50 | 82,471 | unchanged |
| `List[String]` 200k x20 | 58,972 | unchanged (one allocation per string) |
| `Map[Int, Int]` 200k x20 | 48,502 | 17,386 |
| `Map[String, Int]` 200k x20 | 94,777 | 78,012 |
| `String` 1 MB x200 | 8,396 | unchanged |

A map with no removed entries and plain keys and values now copies its slot array and hash index as two blocks instead of rebuilding the index entry by entry.
