+++
title = "fs"
+++

# @std/fs.ms

Import each required symbol with `import Name from "@std/fs.ms"`.

## DirectoryEntry {data-api-kind="Record"}

```manuscript
type DirectoryEntry:
    name: String
    directory: Bool
    symlink: Bool
```

## FileInfo {data-api-kind="Record"}

```manuscript
type FileInfo:
    name: String
    size: Int
    directory: Bool
    symlink: Bool
    modified: Timestamp
```

## FileSystem {data-api-kind="Interface"}

```manuscript
interface FileSystem:
    fn canonicalize(path: String) -> Result[String, FileSystemError]
    fn copy_file(source: String, destination: String, replace: Bool, max_bytes: Int) -> Result[Unit, FileSystemError]
    fn create_directory(path: String, recursive: Bool) -> Result[Unit, FileSystemError]
    fn create_link(path: String, target: String) -> Result[Unit, FileSystemError]
    fn list(path: String, max_entries: Int) -> Result[List[DirectoryEntry], FileSystemError]
    fn read_file(path: String, max_bytes: Int) -> Result[Bytes, FileSystemError]
    fn read_link(path: String) -> Result[String, FileSystemError]
    fn remove(path: String, recursive: Bool) -> Result[Unit, FileSystemError]
    fn rename(source: String, destination: String) -> Result[Unit, FileSystemError]
    fn stat(path: String, follow_links: Bool) -> Result[FileInfo, FileSystemError]
    fn temporary_directory(prefix: String) -> Result[String, FileSystemError]
    fn write_file(path: String, data: Bytes, replace: Bool) -> Result[Unit, FileSystemError]
```

## FileSystemError {data-api-kind="Alternative"}

```manuscript
type FileSystemError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case NotFound
    case AlreadyExists
    case PermissionDenied
    case Unsupported
    case Failed(message: String)
```

```manuscript
impl Error for FileSystemError:
    fn message() -> String
```

