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
    max_entries: Optional[Int] = none
    max_entry_bytes: Optional[Int] = none
    max_total_bytes: Optional[Int] = none
```

## pack {data-api-kind="Function"}

```manuscript
fn pack(entries: List[ArchiveEntry], format: String, max_bytes: Optional[Int] = none) -> Result[Bytes, ArchiveError]
```

## unpack {data-api-kind="Function"}

```manuscript
fn unpack(data: Bytes, format: String, limits: Optional[ArchiveLimits] = none) -> Result[List[ArchiveEntry], ArchiveError]
```

