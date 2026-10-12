+++
title = "archive"
+++

# @std/archive.ms

Import each required symbol with `import Name from "@std/archive.ms"`.

## ArchiveEntry

Kind: record.

```text
ArchiveEntry: ArchiveEntry
field path: String
field data: Bytes
field directory: Bool
```

## ArchiveLimits

Kind: record.

```text
ArchiveLimits: ArchiveLimits
field max_entries: Int
field max_entry_bytes: Int
field max_total_bytes: Int
```

## pack

Kind: fn.

```text
pack: fn(entries: List[ArchiveEntry], format: String, max_bytes: Int)->Result[Bytes, LibraryError]
```

## unpack

Kind: fn.

```text
unpack: fn(data: Bytes, format: String, limits: ArchiveLimits)->Result[List[ArchiveEntry], LibraryError]
```

