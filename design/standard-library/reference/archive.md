+++
title = "archive"
+++

# @std/archive.ms

Import each required symbol with `import Name from "@std/archive.ms"`.

## ArchiveEntry {data-api-kind="Record"}

```manuscript
type ArchiveEntry:
    path: String
    data: Bytes
    directory: Bool
```

## ArchiveLimits {data-api-kind="Record"}

```manuscript
type ArchiveLimits:
    max_entries: Int
    max_entry_bytes: Int
    max_total_bytes: Int
```

## pack {data-api-kind="Function"}

```manuscript
fn pack(entries: List[ArchiveEntry], format: String, max_bytes: Int) -> Result[Bytes, LibraryError]
```

## unpack {data-api-kind="Function"}

```manuscript
fn unpack(data: Bytes, format: String, limits: ArchiveLimits) -> Result[List[ArchiveEntry], LibraryError]
```

