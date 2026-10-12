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

## ArchiveError {data-api-kind="Alternative"}

```manuscript
type ArchiveError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Unsupported
    case Failed(message: String)
```

```manuscript
impl Error for ArchiveError:
    fn message() -> String
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
fn pack(entries: List[ArchiveEntry], format: String, max_bytes: Int) -> Result[Bytes, ArchiveError]
```

## unpack {data-api-kind="Function"}

```manuscript
fn unpack(data: Bytes, format: String, limits: ArchiveLimits) -> Result[List[ArchiveEntry], ArchiveError]
```

