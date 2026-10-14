# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"

# Errors returned when an archive cannot be read or written.
export type ArchiveError:
    # A format argument's entry paths, directory payloads or supplied output/unpack limits are invalid.
    case InvalidInput
    # Archive bytes, duplicate or file/directory-conflicting paths, extracted entry paths or encoded metadata are invalid.
    case InvalidData
    # Encoded bytes, entry count or unpacked per-entry/total bytes exceed a supplied budget.
    case LimitExceeded
    # The selected format or an encountered entry kind is unsupported, such as links or special files.
    case Unsupported
    # An explicit implementation-supplied archive diagnostic; native validation uses specific cases.
    case Failed(
        # Original diagnostic text, returned unchanged by message().
        message: String
    )

# One file or directory in an archive. Paths use forward slashes.
export type ArchiveEntry:
    # Relative forward-slash path; pack/unpack reject traversal, absolute paths and duplicate normalized names. Unpack returns directory paths without a trailing slash.
    path: String
    # File contents as immutable bytes; directory entries must carry empty bytes.
    data: Bytes
    # True for a directory entry rather than a regular file; links and special files are not supported.
    directory: Bool

# Optional limits applied while unpacking untrusted archive data.
export type ArchiveLimits:
    # Maximum unpacked entries, including directories; none adds no entry-count budget.
    max_entries: Optional[Int] = none
    # Maximum unpacked bytes for each entry; zero admits only empty data.
    max_entry_bytes: Optional[Int] = none
    # Cumulative unpacked file bytes across all entries; none adds no total-output budget.
    max_total_bytes: Optional[Int] = none

# Encodes entries as exactly `zip` or `tar` bytes (case-sensitive); others return Unsupported. `max_bytes` bounds output when supplied.
export fn pack(
    entries: List[ArchiveEntry],
    format: String,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, ArchiveError]:

# Decodes exactly `zip` or `tar` (case-sensitive); other formats return Unsupported.
# Applies each supplied entry and total-size limit.
export fn unpack(
    data: Bytes,
    format: String,
    limits: Optional[ArchiveLimits] = none
) -> Result[List[ArchiveEntry], ArchiveError]:

impl Error for ArchiveError:
    # Returns original Failed text, or an archive-prefixed diagnostic for other cases.
    fn message() -> String:

# Selects a supported archive format without a runtime string spelling check.
# Existing pack/unpack format: String calls remain available.
export type ArchiveFormat:
    # ZIP files and directories.
    case Zip
    # TAR files and directories.
    case Tar
    # Packs entries with the same optional output budget and path validation as pack.
    fn pack(
        entries: List[ArchiveEntry],
        max_bytes: Optional[Int] = none
    ) -> Result[Bytes, ArchiveError]:
    # Unpacks in memory with the same entry/byte limits and domain errors as unpack.
    fn unpack(
        data: Bytes,
        limits: Optional[ArchiveLimits] = none
    ) -> Result[List[ArchiveEntry], ArchiveError]:

# documentation documentation/standard-library/archive.md
# +++
# title = "Compression and archives"
# weight = 9
# +++
#
# # Compression and archives
#
# API reference: [compress](reference/compress.md), [archive](reference/archive.md).
#
# Use compress for a byte stream and archive for named file or directory entries. Both operate on data in memory. Set limits on expanded output; unpacking an archive does not write its entries to disk.
#
# ## Typed format selection
#
# Choose `CompressionFormat.Gzip`, `Zlib`, or `Deflate` and call its `compress`/`decompress` operations. Choose `ArchiveFormat.Zip` or `Tar` and call its `pack`/`unpack` operations. These alternatives check the format selection in source while sharing the existing implementations, limits, domain errors, and cancellation. Both compression forms default to level 6, a balanced DEFLATE setting. Explicit levels 0..9 retain their behavior; level 0 stores data. Output-byte limits remain independent of the compression level. Existing explicit string-based calls retain their contracts.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import CompressionFormat from "@std/compress.ms"
# import panic from "@std/faults.ms"
#
# test "use a typed compression format":
#     let format = CompressionFormat.Gzip
#     let input = "hello".to_bytes()
#     let encoded = format.compress(input).unwrap()
#     let decoded = format.decompress(encoded, max_bytes: 5).unwrap()
#     if decoded != input: return panic("compression roundtrip")
# ```
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import {ArchiveFormat, ArchiveEntry} from "@std/archive.ms"
# import List from "@std/collections.ms"
# import panic from "@std/faults.ms"
#
# test "use a typed archive format":
#     let entries = [ArchiveEntry("note.txt", "hello".to_bytes(), false)]
#     let encoded = ArchiveFormat.Zip.pack(entries).unwrap()
#     if ArchiveFormat.Zip.unpack(encoded).unwrap() != entries: return panic("archive roundtrip")
# ```
#
# ## Compression behavior
#
# Supported format strings are exactly the case-sensitive `gzip`, `zlib`, and raw `deflate`; others return `CompressionError.Unsupported`. Compression levels are 0–9 (0 stores data without compression); values outside that range return `InvalidInput`. Output limits must be nonnegative.
#
# Decompression validates checksums and rejects trailing bytes that do not belong to the format. Concatenated gzip members share one cumulative output limit. Chunk processing checks cancellation. Excess expanded output returns `LimitExceeded` before the decoder retains output beyond `max_bytes`.
#
# Gzip output has a zero timestamp and no platform or name metadata.
#
# ## Archive records and limits
#
# `ArchiveEntry` contains `path: String`, `data: Bytes`, and `directory: Bool`. `ArchiveLimits` contains `max_entries: Optional[Int]`, `max_entry_bytes: Optional[Int]`, and `max_total_bytes: Optional[Int]`. All limits are nonnegative and count expanded content.
#
# Pack and unpack accept exactly the case-sensitive strings `zip` and `tar`; other formats return `ArchiveError.Unsupported`. Both support regular files and directories. Names must be UTF-8 portable relative paths. They reject absolute roots, backslashes, colons, NUL, and empty, dot, or dot-dot components. Duplicate normalized paths are rejected, as is a regular file whose path is an ancestor directory of another entry (file `a` with `a/b`), because the two cannot be extracted together; both return `InvalidData`. Directory data must be empty. A ZIP entry name (including a directory's trailing slash) longer than 65535 bytes returns `InvalidInput`; TAR has no such limit. Pack accepts a directory path with or without a trailing slash; unpack always returns it without one, so `unpack(pack(entries))` equals `entries` for canonical (slashless) directory paths.
#
# Encrypted archives, devices, sparse files, links, and non-UTF-8 names are unsupported. ZIP supports stored and deflated entries and validates checksums. Pack preserves entry order with deterministic metadata: TAR uses the epoch and ZIP uses its 1980 minimum date.
#
# | Problem | Error |
# | --- | --- |
# | Unsupported entry type | `Unsupported` |
# | Malformed archive or decoded path | `InvalidData` |
# | Invalid source entry | `InvalidInput` |
#
# ## Unpacking does not write files
#
# `unpack` returns separate data entries. It performs no filesystem writes and grants no filesystem access. Automatic extraction is future work.
#
# Bound compressed input reads as well as expanded output. ZIP parses central-directory metadata before checking `max_entries`. TAR uses native header validation; it makes no canonical guarantee about arbitrary trailing padding or metadata.
#
# An application can validate entries and write them through an explicit FileSystem service. Secure extraction into an existing directory still needs a trusted containment adapter; a lexical path check alone is insufficient. Brotli and Zstd remain future work.
# end-documentation
