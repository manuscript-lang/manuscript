# An extern type is source-constructible when its declaration says so

The C body checker claims `StringBuilder()` and `BytesBuilder()` only because
`stdlib/string_builder.ms` and `stdlib/bytes.ms` put `// ms: constructible` above the type
(`ms_doc_has_marker`, the same comment-marker family as `// ms: data`). Rust accepts `T()` for any
extern type except a hard-coded list (`BigInt`, `Regex`, `Decimal`, `HttpHeaders`, `IpAddress`,
`Cidr`), which are built by literals or functions; a name list in C would copy that idiosyncrasy,
so C declines every unmarked extern construction instead.

- Mark a new builder-like extern type when callers write `T()`; nothing else changes in the checker.
- Types with arguments (`Bytes(values)`) are not covered: the marker means "no fields, no arguments".
- Rust ignores the marker line until the Rust checker is removed.

## Constructors with arguments: `// ms: constructor`

`Bytes(values)` is checked as a call of the function the standard file marks `// ms: constructor` whose
result is that type (`extern fn msrt_bytes_from_values(values: List[UInt8]) Bytes` in `stdlib/bytes.ms`, in
the source half of the mixed file; the lookup also reads the `+source` twin). Rust special-cases `Bytes` and
`Set` by name in `constructor_signature`; C reads the declaration instead, so a new native constructor is
one marked extern function. `Set(values)` is generic and not covered yet.
