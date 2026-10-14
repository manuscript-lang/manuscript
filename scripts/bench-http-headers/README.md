# Header lookup and proxy metadata controls

Run with the pinned Go SDK:

```sh
toolchain/go/bin/go test ./pkg/runtime -run '^$' -bench '^BenchmarkHTTPHeaders$' -benchmem -benchtime=300ms -count=3
```

The fixture has 17 names and 34 separate values, including two Set-Cookie values. This measures ordinary data operations, without network I/O. The retained control rebuilds headers from the same host map on every read. The cached metadata path returns the already stored mutable metadata record and header object. Explicit clone/text controls include the costs requested by those operations; lookup never clones membership.

Linux/amd64, Go 1.25.1, Xeon Platinum 8573C, GOMAXPROCS=4. Raw samples are in samples.txt. Shared-host timings vary and do not establish an application-wide speedup.

| Operation | Time range | Bytes/op | Allocs/op |
| --- | --- | --- | --- |
| Lowercase lookup | measured in samples.txt | 0 | 0 |
| Mixed-case lookup | measured in samples.txt | 16 | 1 |
| Metadata sharing cached headers | 35–49 ns | 0 | 0 |
| Reconvert host headers control | 18.7–20.1 µs | 7680 | 185 |
| Explicit membership clone | measured in samples.txt | 5448 | 65 |
| Explicit two-value text extraction | 1.10–1.49 µs | 456 | 16 |

Mixed-case lookup allocates its ASCII-folded key, not a value list. Metadata reuses the stored record, header object and every value list. Status/headers edits are alias-visible without changing the wire response. Conversion is paid once when each HTTP request/response enters the runtime. Callers select clone when independent membership is needed. No copy-on-read guarantee is imposed for convenience.
