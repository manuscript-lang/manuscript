# Header lookup and proxy metadata controls

Run with the pinned Go SDK:

```sh
toolchain/go/bin/go test ./pkg/runtime -run '^$' -bench '^BenchmarkHTTPHeaders$' -benchmem -benchtime=300ms -count=3
```

The fixture has 17 names and 34 separate values, including two Set-Cookie values. This measures ordinary data operations, without network I/O. The retained control rebuilds headers from the same host map on every read. The cached metadata path returns a status record sharing the already converted header object. Explicit clone/text controls include the costs requested by those operations; lookup never clones membership.

Linux/amd64, Go 1.25.1, Xeon Platinum 8573C, four benchmark workers. Raw samples are in samples.txt. Shared-host timings vary and do not establish an application-wide speedup.

| Operation | Time range | Bytes/op | Allocs/op |
| --- | --- | --- | --- |
| Lowercase lookup | 28–31 ns | 0 | 0 |
| Mixed-case lookup | 64–88 ns | 16 | 1 |
| Metadata sharing cached headers | 417–438 ns | 360 | 3 |
| Reconvert host headers control | 16.8–17.0 µs | 7680 | 185 |
| Explicit membership clone | 7.9–8.5 µs | 5448 | 65 |
| Explicit two-value text extraction | 1.15–1.39 µs | 456 | 16 |

Mixed-case lookup allocates its ASCII-folded key, not a value list. Metadata allocates a status snapshot; it shares the header object and every value list. Conversion is paid once when each HTTP request/response enters the runtime. Callers select clone when independent membership is needed. No copy-on-read guarantee is imposed for convenience.
