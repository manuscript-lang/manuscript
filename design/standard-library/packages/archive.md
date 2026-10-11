+++
title = "Compression and archives"
weight = 58
+++

# Compression and archives

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

## `@std/compress.ms`

```text
fn compress(data: Bytes, format: String, level: Int, max_bytes: Int) -> Result[Bytes, LibraryError]
fn decompress(data: Bytes, format: String, max_bytes: Int) -> Result[Bytes, LibraryError]
```

## `@std/archive.ms`

```text
fn pack(entries: List[ArchiveEntry], format: String, max_bytes: Int) -> Result[Bytes, LibraryError]
fn unpack(data: Bytes, format: String, limits: ArchiveLimits) -> Result[List[ArchiveEntry], LibraryError]
```

Compression format strings are gzip, zlib and deflate; other formats return Unsupported. Levels 0–9 and nonnegative output bounds are required. Decompress validates checksums, accepts concatenated gzip members under one cumulative limit, and rejects trailing non-format bytes. Incremental chunk processing checks cancellation; a decompression bomb returns LimitExceeded before retaining expanded output beyond max_bytes. Gzip emission has zero timestamp and no platform/name metadata.

ArchiveEntry fields `path: String`, `data: Bytes`, `directory: Bool`; ArchiveLimits fields `max_entries: Int`, `max_entry_bytes: Int`, `max_total_bytes: Int`. Limits count expanded content and are nonnegative. Pack/unpack support format strings zip/tar, UTF-8 portable relative entry names, regular files and directories; no encrypted archives, device files, sparse files, links or non-UTF-8 names. Entry paths reject absolute roots, backslash, colon, NUL, empty/dot/dot-dot components. Duplicate normalized paths reject. Directory data must be empty. ZIP supports stored/deflated data and validates checksums. Pack retains entry order with deterministic metadata (TAR epoch; ZIP 1980 minimum date). Unsupported types return Unsupported, malformed archive/path returns InvalidData, invalid source entries return InvalidInput.

Unpack returns immutable data and never writes to disk or grants authority. ZIP's directory metadata is parsed before max_entries can be checked; applications must bound compressed input reads as well as expanded limits. TAR uses native header validation; arbitrary trailing padding/metadata is not a canonical format guarantee. Automatic filesystem extraction is deferred, rather than exposing a lexical-only containment check. Applications can validate decoded entries and write them through explicitly authorized FileSystem operations, but must not claim secure extraction into an existing directory without a trusted containment adapter. Brotli/Zstd remain deferred.
