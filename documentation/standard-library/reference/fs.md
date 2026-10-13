+++
title = "fs"
+++

# @std/fs.ms

Import each required symbol with `import Name from "@std/fs.ms"`.

## CopyOptions {data-api-kind="Record"}

Policies for recursive copies, including replacement, symlinks, and optional limits.

```manuscript
type CopyOptions:
    recursive: Bool
    replace: Bool
    error_on_exists: Bool
    dereference: Bool
    preserve_timestamps: Bool
    verbatim_symlinks: Bool
    clone: String
    max_entries: Optional[Int] = none
    max_bytes: Optional[Int] = none
```

## Directory {data-api-kind="Interface"}

An open directory that yields one child per read and must be closed.

```manuscript
interface Directory:
    fn path() -> String
    fn close() -> Unit
    fn read() -> Result[Optional[DirectoryEntry], FileSystemError]
```

## DirectoryEntry {data-api-kind="Record"}

The name and kind flags for one child returned by a directory listing.

```manuscript
type DirectoryEntry:
    name: String
    directory: Bool
    symlink: Bool
```

## FileEvent {data-api-kind="Record"}

One filesystem change and the affected path.

```manuscript
type FileEvent:
    path: String
    kind: String
```

## FileHandle {data-api-kind="Interface"}

An open file supporting sequential and positional I/O.

```manuscript
interface FileHandle:
    fn reader() -> ReadStream
    fn writer() -> WriteStream
    fn close() -> Unit
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], FileSystemError]
    fn write(data: Bytes) -> Result[Int, FileSystemError]
    fn append_file(data: Bytes) -> Result[Unit, FileSystemError]
    fn read_at(offset: Int, max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
    fn write_at(offset: Int, data: Bytes) -> Result[Int, FileSystemError]
    fn read_file(max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
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
    fn read_lines(max_bytes: Optional[Int] = none, max_lines: Optional[Int] = none) -> Result[List[String], FileSystemError]
```

## FileInfo {data-api-kind="Record"}

File metadata, including portable fields and exact platform-specific numeric values.

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

Filesystem operations and resource factories for the current host.

```manuscript
interface FileSystem:
    fn open_flags(path: String, flags: Int, mode: Int) -> Result[FileHandle, FileSystemError]
    fn glob_entries(path: String, options: GlobOptions, exclude: Optional[fn(entry: PathEntry) -> Bool]) -> Result[List[PathEntry], FileSystemError]
    fn copy(source: String, destination: String, options: CopyOptions, filter: Optional[fn(source: String, destination: String) -> Bool]) -> Result[Unit, FileSystemError]
    fn watch_native(path: String, recursive: Bool, max_entries: Optional[Int] = none, max_events: Optional[Int] = none, overflow: String) -> Result[FileWatcher, FileSystemError]
    fn canonicalize(path: String) -> Result[String, FileSystemError]
    fn copy_file(source: String, destination: String, replace: Bool, max_bytes: Optional[Int] = none) -> Result[Unit, FileSystemError]
    fn create_directory(path: String, recursive: Bool) -> Result[Unit, FileSystemError]
    fn create_link(path: String, target: String) -> Result[Unit, FileSystemError]
    fn list(path: String, max_entries: Optional[Int] = none) -> Result[List[DirectoryEntry], FileSystemError]
    fn read_file(path: String, max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
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
    fn copy_tree(source: String, destination: String, replace: Bool, max_entries: Optional[Int] = none, max_bytes: Optional[Int] = none) -> Result[Unit, FileSystemError]
    fn glob(path: String, pattern: String, max_entries: Optional[Int] = none) -> Result[List[String], FileSystemError]
    fn watch(path: String, recursive: Bool, interval: Duration, max_entries: Optional[Int] = none) -> Result[FileWatcher, FileSystemError]
    fn temporary(prefix: String) -> Result[TemporaryDirectory, FileSystemError]
    fn stat_filesystem(path: String) -> Result[FileSystemInfo, FileSystemError]
    fn chmod_link(path: String, mode: Int) -> Result[Unit, FileSystemError]
```

## FileSystemError {data-api-kind="Alternative"}

Errors returned by filesystem operations. `Failed` retains the host error text.

```manuscript
type FileSystemError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case NotFound
    case AlreadyExists
    case NotEmpty
    case PermissionDenied
    case Unsupported
    case Closed
    case Failed(message: String)
```

```manuscript
impl Error for FileSystemError:
    fn message() -> String:
```

## FileSystemInfo {data-api-kind="Record"}

Capacity and free-space statistics for the filesystem containing a path.

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

A change stream returned by a filesystem watch operation.

```manuscript
interface FileWatcher:
    fn close() -> Unit
    fn next() -> Result[List[FileEvent], FileSystemError]
```

## GlobOptions {data-api-kind="Record"}

Include and exclude patterns and limits used by filesystem glob operations.

```manuscript
type GlobOptions:
    patterns: List[String]
    exclude: List[String]
    follow_links: Bool
    max_entries: Optional[Int] = none
    max_results: Optional[Int] = none
```

## PathEntry {data-api-kind="Record"}

A matched path together with its filesystem entry metadata.

```manuscript
type PathEntry:
    path: String
    entry: DirectoryEntry
```

## TemporaryDirectory {data-api-kind="Interface"}

A temporary directory whose contents are removed when it is closed.

```manuscript
interface TemporaryDirectory:
    fn close() -> Unit
    fn path() -> String
```

## constants {data-api-kind="Function"}

Returns host filesystem flag, mode, and permission constants by name.

```manuscript
fn constants() -> Map[String, Int]:
```

## filesystem {data-api-kind="Function"}

Returns filesystem operations for the current host.

```manuscript
fn filesystem() -> FileSystem:
```

