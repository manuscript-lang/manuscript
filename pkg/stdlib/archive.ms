# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

# Errors returned when an archive cannot be read or written.
export type ArchiveError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Unsupported
    case Failed(message: String)

# One file or directory in an archive. Paths use forward slashes.
export type ArchiveEntry:
    path: String
    data: Bytes
    directory: Bool

# Optional limits applied while unpacking untrusted archive data.
export type ArchiveLimits:
    max_entries: Optional[Int] = none
    max_entry_bytes: Optional[Int] = none
    max_total_bytes: Optional[Int] = none

# Encodes entries as `zip` or `tar` bytes. `max_bytes` bounds output when supplied.
export fn pack(
    entries: List[ArchiveEntry],
    format: String,
    max_bytes: Optional[Int] = none
) -> Result[Bytes, ArchiveError]:

# Decodes `zip` or `tar` bytes and applies each supplied entry and total-size limit.
export fn unpack(
    data: Bytes,
    format: String,
    limits: Optional[ArchiveLimits] = none
) -> Result[List[ArchiveEntry], ArchiveError]:

impl Error for ArchiveError:
    fn message() -> String:
