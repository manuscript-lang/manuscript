+++
title = "archive"
+++

# @std/archive.ms

Import each required symbol with `import Name from "@std/archive.ms"`.

## ArchiveEntry {data-api-kind="Record"}

One file or directory in an archive. Paths use forward slashes.

```manuscript
type ArchiveEntry:
    path: String
    data: Bytes
    directory: Bool
```

## ArchiveError {data-api-kind="Alternative"}

Errors returned when an archive cannot be read or written.

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
    fn message() -> String:
```

## ArchiveFormat {data-api-kind="Alternative"}

Selects a supported archive format without a runtime string spelling check.
Existing pack/unpack format: String calls remain available.

```manuscript
type ArchiveFormat:
    case Zip
    case Tar
    fn pack(entries: List[ArchiveEntry], max_bytes: Optional[Int] = none) -> Result[Bytes, ArchiveError]:
    fn unpack(data: Bytes, limits: Optional[ArchiveLimits] = none) -> Result[List[ArchiveEntry], ArchiveError]:
```

### ArchiveFormat.Tar

TAR files and directories.

```manuscript
case Tar
```

### ArchiveFormat.Zip

ZIP files and directories.

```manuscript
case Zip
```

### ArchiveFormat.pack

Packs entries with the same optional output budget and path validation as pack.

```manuscript
fn pack(entries: List[ArchiveEntry], max_bytes: Optional[Int] = none) -> Result[Bytes, ArchiveError]:
```

### ArchiveFormat.unpack

Unpacks in memory with the same entry/byte limits and domain errors as unpack.

```manuscript
fn unpack(data: Bytes, limits: Optional[ArchiveLimits] = none) -> Result[List[ArchiveEntry], ArchiveError]:
```

## ArchiveLimits {data-api-kind="Record"}

Optional limits applied while unpacking untrusted archive data.

```manuscript
type ArchiveLimits:
    max_entries: Optional[Int] = none
    max_entry_bytes: Optional[Int64] = none
    max_total_bytes: Optional[Int64] = none
```

## pack {data-api-kind="Function"}

Encodes entries as exactly `zip` or `tar` bytes (case-sensitive); others return Unsupported. `max_bytes` bounds output when supplied.

```manuscript
fn pack(entries: List[ArchiveEntry], format: String, max_bytes: Optional[Int64] = none) -> Result[Bytes, ArchiveError]:
```

## unpack {data-api-kind="Function"}

Decodes exactly `zip` or `tar` (case-sensitive); other formats return Unsupported.
Applies each supplied entry and total-size limit.

```manuscript
fn unpack(data: Bytes, format: String, limits: Optional[ArchiveLimits] = none) -> Result[List[ArchiveEntry], ArchiveError]:
```

