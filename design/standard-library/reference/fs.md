+++
title = "fs"
+++

# @std/fs.ms

Import each required symbol with `import Name from "@std/fs.ms"`.

## CopyOptions {data-api-kind="Record"}

```manuscript
type CopyOptions:
    recursive: Bool
    replace: Bool
    error_on_exists: Bool
    dereference: Bool
    preserve_timestamps: Bool
    verbatim_symlinks: Bool
    clone: String
    max_entries: Int
    max_bytes: Int
```

## Directory {data-api-kind="Interface"}

```manuscript
interface Directory:
    fn path() -> String
    fn close() -> Unit
    fn read() -> Result[Optional[DirectoryEntry], FileSystemError]
```

## DirectoryEntry {data-api-kind="Record"}

```manuscript
type DirectoryEntry:
    name: String
    directory: Bool
    symlink: Bool
```

## FileEvent {data-api-kind="Record"}

```manuscript
type FileEvent:
    path: String
    kind: String
```

## FileHandle {data-api-kind="Interface"}

```manuscript
interface FileHandle:
    fn reader() -> ReadStream
    fn writer() -> WriteStream
    fn close() -> Unit
    fn read(max_bytes: Int) -> Result[Optional[Bytes], FileSystemError]
    fn write(data: Bytes) -> Result[Int, FileSystemError]
    fn append_file(data: Bytes) -> Result[Unit, FileSystemError]
    fn read_at(offset: Int, max_bytes: Int) -> Result[Bytes, FileSystemError]
    fn write_at(offset: Int, data: Bytes) -> Result[Int, FileSystemError]
    fn read_file(max_bytes: Int) -> Result[Bytes, FileSystemError]
    fn write_file(data: Bytes) -> Result[Unit, FileSystemError]
    fn read_vectors(sizes: List[Int], offset: Int) -> Result[List[Bytes], FileSystemError]
    fn write_vectors(buffers: List[Bytes], offset: Int) -> Result[Int, FileSystemError]
    fn seek(offset: Int, origin: Int) -> Result[Int, FileSystemError]
    fn stat() -> Result[FileInfo, FileSystemError]
    fn truncate(size: Int) -> Result[Unit, FileSystemError]
    fn sync() -> Result[Unit, FileSystemError]
    fn data_sync() -> Result[Unit, FileSystemError]
    fn chmod(mode: Int) -> Result[Unit, FileSystemError]
    fn chown(uid: Int, gid: Int) -> Result[Unit, FileSystemError]
    fn set_times(accessed: Timestamp, modified: Timestamp) -> Result[Unit, FileSystemError]
    fn read_lines(max_bytes: Int, max_lines: Int) -> Result[List[String], FileSystemError]
```

## FileInfo {data-api-kind="Record"}

```manuscript
type FileInfo:
    name: String
    size: Int
    directory: Bool
    symlink: Bool
    modified: Timestamp
    accessed: Timestamp
    changed: Timestamp
    mode: Int
    permissions: Int
    created: Optional[Timestamp]
    block_size: Int
    blocks: Int
    rdev: Int
    fifo: Bool
    socket: Bool
    block_device: Bool
    char_device: Bool
    exact: Map[String, BigInt]
    regular: Bool
    device: Int
    inode: Int
    links: Int
    uid: Int
    gid: Int
```

## FileSystem {data-api-kind="Interface"}

```manuscript
interface FileSystem:
    fn open_flags(path: String, flags: Int, mode: Int) -> Result[FileHandle, FileSystemError]
    fn glob_entries(path: String, options: GlobOptions, exclude: Optional[fn(entry: PathEntry) -> Bool]) -> Result[List[PathEntry], FileSystemError]
    fn copy(source: String, destination: String, options: CopyOptions, filter: Optional[fn(source: String, destination: String) -> Bool]) -> Result[Unit, FileSystemError]
    fn watch_native(path: String, recursive: Bool, max_entries: Int, max_events: Int, overflow: String) -> Result[FileWatcher, FileSystemError]
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
    fn access(path: String, mode: Int) -> Result[Unit, FileSystemError]
    fn append_file(path: String, data: Bytes) -> Result[Unit, FileSystemError]
    fn chmod(path: String, mode: Int) -> Result[Unit, FileSystemError]
    fn chown(path: String, uid: Int, gid: Int, follow_links: Bool) -> Result[Unit, FileSystemError]
    fn truncate(path: String, size: Int) -> Result[Unit, FileSystemError]
    fn set_times(path: String, accessed: Timestamp, modified: Timestamp, follow_links: Bool) -> Result[Unit, FileSystemError]
    fn hard_link(source: String, destination: String) -> Result[Unit, FileSystemError]
    fn open(path: String, flags: String, mode: Int) -> Result[FileHandle, FileSystemError]
    fn open_directory(path: String) -> Result[Directory, FileSystemError]
    fn copy_tree(source: String, destination: String, replace: Bool, max_entries: Int, max_bytes: Int) -> Result[Unit, FileSystemError]
    fn glob(path: String, pattern: String, max_entries: Int) -> Result[List[String], FileSystemError]
    fn watch(path: String, recursive: Bool, interval: Duration, max_entries: Int) -> Result[FileWatcher, FileSystemError]
    fn temporary(prefix: String) -> Result[TemporaryDirectory, FileSystemError]
    fn stat_filesystem(path: String) -> Result[FileSystemInfo, FileSystemError]
    fn chmod_link(path: String, mode: Int) -> Result[Unit, FileSystemError]
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
    case Closed
    case Failed(message: String)
```

```manuscript
impl Error for FileSystemError:
    fn message() -> String
```

## FileSystemInfo {data-api-kind="Record"}

```manuscript
type FileSystemInfo:
    type_id: Int
    block_size: Int
    blocks: Int
    blocks_free: Int
    blocks_available: Int
    files: Int
    files_free: Int
```

## FileWatcher {data-api-kind="Interface"}

```manuscript
interface FileWatcher:
    fn close() -> Unit
    fn next() -> Result[List[FileEvent], FileSystemError]
```

## GlobOptions {data-api-kind="Record"}

```manuscript
type GlobOptions:
    patterns: List[String]
    exclude: List[String]
    follow_links: Bool
    max_entries: Int
    max_results: Int
```

## PathEntry {data-api-kind="Record"}

```manuscript
type PathEntry:
    path: String
    entry: DirectoryEntry
```

## TemporaryDirectory {data-api-kind="Interface"}

```manuscript
interface TemporaryDirectory:
    fn close() -> Unit
    fn path() -> String
```

## constants {data-api-kind="Function"}

```manuscript
fn constants() -> Map[String, Int]
```

## filesystem {data-api-kind="Function"}

```manuscript
fn filesystem() -> FileSystem
```

