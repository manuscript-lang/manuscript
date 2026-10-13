+++
title = "Compression and archives"
weight = 9
+++

# Compression and archives

API reference: [compress](reference/compress.md), [archive](reference/archive.md).

Use compress for a byte stream and archive for named file or directory entries. Both operate on data in memory. Set limits on expanded output; unpacking an archive does not write its entries to disk.

## Compression behavior

Supported format strings are exactly the case-sensitive `gzip`, `zlib`, and raw `deflate`; others return `CompressionError.Unsupported`. Compression levels are 0–9 (0 stores data without compression); values outside that range return `InvalidInput`. Output limits must be nonnegative.

Decompression validates checksums and rejects trailing bytes that do not belong to the format. Concatenated gzip members share one cumulative output limit. Chunk processing checks cancellation. Excess expanded output returns `LimitExceeded` before the decoder retains output beyond `max_bytes`.

Gzip output has a zero timestamp and no platform or name metadata.

## Archive records and limits

`ArchiveEntry` contains `path: String`, `data: Bytes`, and `directory: Bool`. `ArchiveLimits` contains `max_entries: Optional[Int]`, `max_entry_bytes: Optional[Int]`, and `max_total_bytes: Optional[Int]`. All limits are nonnegative and count expanded content.

Pack and unpack accept exactly the case-sensitive strings `zip` and `tar`; other formats return `ArchiveError.Unsupported`. Both support regular files and directories. Names must be UTF-8 portable relative paths. They reject absolute roots, backslashes, colons, NUL, and empty, dot, or dot-dot components. Duplicate normalized paths are rejected. Directory data must be empty.

Encrypted archives, devices, sparse files, links, and non-UTF-8 names are unsupported. ZIP supports stored and deflated entries and validates checksums. Pack preserves entry order with deterministic metadata: TAR uses the epoch and ZIP uses its 1980 minimum date.

| Problem | Error |
| --- | --- |
| Unsupported entry type | `Unsupported` |
| Malformed archive or decoded path | `InvalidData` |
| Invalid source entry | `InvalidInput` |

## Unpacking does not write files

`unpack` returns separate data entries. It performs no filesystem writes and grants no filesystem access. Automatic extraction is future work.

Bound compressed input reads as well as expanded output. ZIP parses central-directory metadata before checking `max_entries`. TAR uses native header validation; it makes no canonical guarantee about arbitrary trailing padding or metadata.

An application can validate entries and write them through an explicit FileSystem service. Secure extraction into an existing directory still needs a trusted containment adapter; a lexical path check alone is insufficient. Brotli and Zstd remain future work.
