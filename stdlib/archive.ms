# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import LibraryError from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type ArchiveEntry:
    path: String
    data: Bytes
    directory: Bool

export type ArchiveLimits:
    max_entries: Int
    max_entry_bytes: Int
    max_total_bytes: Int

export fn pack(entries: List[ArchiveEntry], format: String, max_bytes: Int) -> Result[Bytes, LibraryError]

export fn unpack(data: Bytes, format: String, limits: ArchiveLimits) -> Result[List[ArchiveEntry], LibraryError]
