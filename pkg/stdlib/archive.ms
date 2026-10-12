# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type ArchiveError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Unsupported
    case Failed(message: String)

export type ArchiveEntry:
    path: String
    data: Bytes
    directory: Bool

export type ArchiveLimits:
    max_entries: Optional[Int] = none
    max_entry_bytes: Optional[Int] = none
    max_total_bytes: Optional[Int] = none

export fn pack(entries: List[ArchiveEntry], format: String, max_bytes: Optional[Int] = none) -> Result[Bytes, ArchiveError]

export fn unpack(data: Bytes, format: String, limits: Optional[ArchiveLimits] = none) -> Result[List[ArchiveEntry], ArchiveError]

impl Error for ArchiveError:
    fn message() -> String
