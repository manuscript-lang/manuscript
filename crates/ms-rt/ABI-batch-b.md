# ABI choices made by the batch B natives

These layouts are decisions made while implementing `ms-std-{encoding,csv,url,path,compress,crypto,regex,archive,json,html}`.
They follow [ABI.md](ABI.md) and have not yet been exercised by lowering; confirm them there before relying on them.

- **Enums** (`HashAlgorithm`, `Curve`, flags) cross as their case index (`i64`). An out-of-range index returns `Unsupported` (hash) or `InvalidInput` (curve) for fallible calls and `false` for verifiers.
- **Records**: `Url { scheme, host, port: Optional[Int], path, query, fragment }` is `UrlRec` in `ms-std-url/src/ffi.rs` (strings +1 when written by the runtime, borrowed when read). `QueryEntry { key, value }` is stored inline, 16 bytes, in a `List` with `DESC_QUERY_ENTRY`. `ArchiveEntry` follows the same rule in `ms-std-archive`.
- **Optionals** are flattened to `has: u8, value` parameters or record fields.
- **Status codes**: `CryptoError` is its case index (InvalidInput 0 is reported as status 1+, see `CryptoFail::status`); `Fail` maps InvalidInput, InvalidData, LimitExceeded.
- **Recursive sum types**: `JsonValue` and `HtmlNode` have no flat layout. `ms-std-json` exposes a `DocObj` handle and `ms-std-html` a `TreeObj` handle with node-id accessors and a builder; lowering decides how to materialize them.
- **Handles** (`Hasher`, `DocObj`, `TreeObj`) are `Obj { rc, drop }` allocated with `msrt_alloc`.
- **semver**: `Version { major, minor, patch: Int, prerelease, build: List[String] }` is `VersionRec` (24-byte `VecVal` lists, declaration order). `SemverError` statuses: InvalidData 4, OutOfRange 2.
- **random**: only the OS source is a native symbol (`msstd_random_os_bytes`; a `Failed` status carries its text through `msstd_random_failure_message`). The algorithms over an `Entropy` are Manuscript in `pkg/stdlib/random.ms`.
- **log**: `Logger` natives are a `LoggerObj` handle. `msrt_log_logger_encode` returns the JSON line to write (the caller passes the clock and owns the transport, interface dispatch and `record`/`bind` field encoding; `msrt_log_object_text` is the `data` wrapper).
- **compress streams**: `DecoderObj`/`EncoderObj` handles. The generated code runs the pull loop: `decoder_poll` returns 0 (output), `POLL_NEED_INPUT` (64) or `POLL_DONE` (65); feed chunks with `feed`, signal the end with `finish_input`. The encoder is `feed` / `finish` / `take`. Bytes delivered before a decode error can differ from Go's chunking.
- **Reuse**: `ms_std_path::glob` is the shared glob matcher (fs should call it).

## Known differences from the Go runtime

- Compressed bytes and zip sizes differ (different deflate/zstd encoders); decompression and round-trips match.
- ECDSA, RSA-PSS and RSA-OAEP outputs are randomized in both runtimes; the fixtures check success parity and verify Go-produced values in Rust.
- GNU sparse tar members are reported as unsupported. Compression stream wrappers are not implemented.
- Private-key parsing mirrors Go (trailing bytes after the PKCS#8 element and an altered embedded EC public key are accepted); other malformed-DER edge cases may differ.
