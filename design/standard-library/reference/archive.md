+++
title = "archive"
+++

# @std/archive.ms

Import each required symbol with `import Name from "@std/archive.ms"`.

## ArchiveEntry {data-api-kind="Record"}

```manuscript
ArchiveEntry: ArchiveEntry
field path: String
field data: Bytes
field directory: Bool
```

## ArchiveLimits {data-api-kind="Record"}

```manuscript
ArchiveLimits: ArchiveLimits
field max_entries: Int
field max_entry_bytes: Int
field max_total_bytes: Int
```

## pack {data-api-kind="Function"}

```manuscript
pack: fn(entries: List[ArchiveEntry], format: String, max_bytes: Int)->Result[Bytes, LibraryError]
```

## unpack {data-api-kind="Function"}

```manuscript
unpack: fn(data: Bytes, format: String, limits: ArchiveLimits)->Result[List[ArchiveEntry], LibraryError]
```

