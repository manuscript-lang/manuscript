import Bytes from "@std/bytes.ms"

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
) Result[Bytes, ArchiveError]:

# Decodes exactly `zip` or `tar` (case-sensitive); other formats return Unsupported.
# Applies each supplied entry and total-size limit.
export fn unpack(
    data: Bytes,
    format: String,
    limits: Optional[ArchiveLimits] = none
) Result[List[ArchiveEntry], ArchiveError]:

impl Error for ArchiveError:
    # Returns original Failed text, or an archive-prefixed diagnostic for other cases.
    fn message() String:

# Selects a supported archive format without a runtime string spelling check.
# Existing pack/unpack format: String calls remain available.
export type ArchiveFormat:
    # ZIP files and directories.
    case Zip
    # TAR files and directories.
    case Tar

impl ArchiveFormat:
    # Packs entries with the same optional output budget and path validation as pack.
    fn pack(
        entries: List[ArchiveEntry],
        max_bytes: Optional[Int] = none
    ) Result[Bytes, ArchiveError]:

    # Unpacks in memory with the same entry/byte limits and domain errors as unpack.
    fn unpack(
        data: Bytes,
        limits: Optional[ArchiveLimits] = none
    ) Result[List[ArchiveEntry], ArchiveError]:
