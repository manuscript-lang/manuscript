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
    max_bytes: Optional[Int64] = none
```

### CopyOptions.clone

Exactly `none`, `try`, or `force`; other strings return InvalidInput.
try falls back to byte copying; force requires a native clone operation.

```manuscript
clone: String
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

### FileEvent.kind

Exactly `rename` (appearance/disappearance/rename) or `change` (contents/metadata).

```manuscript
kind: String
```

## FileHandle {data-api-kind="Interface"}

An open file supporting sequential and positional I/O.

```manuscript
interface FileHandle:
    fn reader() -> ReadStream
    fn writer() -> WriteStream
    fn close() -> Unit
    fn read(max_bytes: Optional[Int64] = none) -> Result[Optional[Bytes], FileSystemError]
    fn write(data: Bytes) -> Result[Int64, FileSystemError]
    fn append_file(data: Bytes) -> Result[Unit, FileSystemError]
    fn read_at(offset: Int64, max_bytes: Optional[Int64] = none) -> Result[Bytes, FileSystemError]
    fn write_at(offset: Int64, data: Bytes) -> Result[Int64, FileSystemError]
    fn read_file(max_bytes: Optional[Int64] = none) -> Result[Bytes, FileSystemError]
    fn write_file(data: Bytes) -> Result[Unit, FileSystemError]
    fn read_vectors(sizes: List[Int], offset: Int64) -> Result[List[Bytes], FileSystemError]
    fn write_vectors(buffers: List[Bytes], offset: Int64) -> Result[Int64, FileSystemError]
    fn seek(offset: Int64, origin: Int) -> Result[Int64, FileSystemError]
    fn stat() -> Result[FileInfo, FileSystemError]
    fn truncate(size: Int64) -> Result[Unit, FileSystemError]
    fn sync() -> Result[Unit, FileSystemError]
    fn data_sync() -> Result[Unit, FileSystemError]
    fn chmod(mode: Int) -> Result[Unit, FileSystemError]
    fn chown(uid: Int64, gid: Int64) -> Result[Unit, FileSystemError]
    fn set_times(accessed: Timestamp, modified: Timestamp) -> Result[Unit, FileSystemError]
    fn read_lines(max_bytes: Optional[Int64] = none, max_lines: Optional[Int] = none) -> Result[List[String], FileSystemError]
```

### FileHandle.append_file

Writes at the current position; appends only when the handle was opened in append mode.

```manuscript
fn append_file(data: Bytes) -> Result[Unit, FileSystemError]
```

### FileHandle.read

Returns a positive chunk (at most 64 KiB), or none at EOF; a supplied size must be positive.

```manuscript
fn read(max_bytes: Optional[Int64] = none) -> Result[Optional[Bytes], FileSystemError]
```

### FileHandle.read_at

Reads at a nonnegative byte offset without moving the position; short/empty Bytes mark EOF.

```manuscript
fn read_at(offset: Int64, max_bytes: Optional[Int64] = none) -> Result[Bytes, FileSystemError]
```

### FileHandle.read_file

Reads remaining bytes from the current position; EOF returns empty Bytes.

```manuscript
fn read_file(max_bytes: Optional[Int64] = none) -> Result[Bytes, FileSystemError]
```

### FileHandle.reader

Adapts this handle to IoError/Optional chunk reads; closing either view closes all aliases.

```manuscript
fn reader() -> ReadStream
```

### FileHandle.seek

Seeks in bytes with origin exactly 0 (start), 1 (current), or 2 (end).
Other origins return InvalidInput; the OS validates the resulting offset.

```manuscript
fn seek(offset: Int64, origin: Int) -> Result[Int64, FileSystemError]
```

### FileHandle.write

Writes all bytes on success and returns their count; errors can leave a prefix without a count.

```manuscript
fn write(data: Bytes) -> Result[Int64, FileSystemError]
```

### FileHandle.write_at

Writes all bytes at a nonnegative offset without moving the position; returns the full count.

```manuscript
fn write_at(offset: Int64, data: Bytes) -> Result[Int64, FileSystemError]
```

### FileHandle.write_file

Writes all bytes at the current position; does not truncate or reposition this handle.

```manuscript
fn write_file(data: Bytes) -> Result[Unit, FileSystemError]
```

### FileHandle.write_vectors

Writes every buffer and returns the total byte count; offset -1 uses the current position.

```manuscript
fn write_vectors(buffers: List[Bytes], offset: Int64) -> Result[Int64, FileSystemError]
```

### FileHandle.writer

Adapts complete writes to IoError/Unit; flush synchronizes the file.

```manuscript
fn writer() -> WriteStream
```

## FileInfo {data-api-kind="Record"}

File metadata, including portable fields and exact platform-specific numeric values.

```manuscript
type FileInfo:
    name: String
    size: Int64
    directory: Bool
    symlink: Bool
    modified: Timestamp
    accessed: Timestamp
    changed: Timestamp
    mode: Int
    permissions: Int
    created: Optional[Timestamp]
    block_size: Int64
    blocks: Int64
    rdev: Int64
    fifo: Bool
    socket: Bool
    block_device: Bool
    char_device: Bool
    exact: Map[String, BigInt]
    regular: Bool
    device: Int64
    inode: Int64
    links: Int64
    uid: Int64
    gid: Int64
```

### FileInfo.block_size

Preferred I/O block size in bytes; unavailable fields are zero.

```manuscript
block_size: Int64
```

### FileInfo.blocks

Allocated 512-byte blocks on POSIX hosts; unavailable fields are zero.

```manuscript
blocks: Int64
```

### FileInfo.size

File length in bytes.

```manuscript
size: Int64
```

## FileSystem {data-api-kind="Interface"}

Filesystem operations and resource factories for the current host.

```manuscript
interface FileSystem:
    fn open_flags(path: String, flags: Int64, mode: Int) -> Result[FileHandle, FileSystemError]
    fn glob_entries(path: String, options: GlobOptions, exclude: Optional[fn(entry: PathEntry) -> Bool]) -> Result[List[PathEntry], FileSystemError]
    fn copy(source: String, destination: String, options: CopyOptions, filter: Optional[fn(source: String, destination: String) -> Bool]) -> Result[Unit, FileSystemError]
    fn watch_native(path: String, recursive: Bool, max_entries: Optional[Int] = none, max_events: Optional[Int] = none, overflow: String) -> Result[FileWatcher, FileSystemError]
    fn canonicalize(path: String) -> Result[String, FileSystemError]
    fn copy_file(source: String, destination: String, replace: Bool = false, max_bytes: Optional[Int64] = none) -> Result[Unit, FileSystemError]
    fn create_directory(path: String, recursive: Bool = false) -> Result[Unit, FileSystemError]
    fn create_link(path: String, target: String) -> Result[Unit, FileSystemError]
    fn list(path: String, max_entries: Optional[Int] = none) -> Result[List[DirectoryEntry], FileSystemError]
    fn read_file(path: String, max_bytes: Optional[Int64] = none) -> Result[Bytes, FileSystemError]
    fn read_link(path: String) -> Result[String, FileSystemError]
    fn remove(path: String, recursive: Bool = false) -> Result[Unit, FileSystemError]
    fn rename(source: String, destination: String) -> Result[Unit, FileSystemError]
    fn stat(path: String, follow_links: Bool) -> Result[FileInfo, FileSystemError]
    fn temporary_directory(prefix: String) -> Result[String, FileSystemError]
    fn write_file(path: String, data: Bytes, replace: Bool = false) -> Result[Unit, FileSystemError]
    fn access(path: String, mode: Int) -> Result[Unit, FileSystemError]
    fn append_file(path: String, data: Bytes) -> Result[Unit, FileSystemError]
    fn chmod(path: String, mode: Int) -> Result[Unit, FileSystemError]
    fn chown(path: String, uid: Int64, gid: Int64, follow_links: Bool) -> Result[Unit, FileSystemError]
    fn truncate(path: String, size: Int64) -> Result[Unit, FileSystemError]
    fn set_times(path: String, accessed: Timestamp, modified: Timestamp, follow_links: Bool) -> Result[Unit, FileSystemError]
    fn hard_link(source: String, destination: String) -> Result[Unit, FileSystemError]
    fn open(path: String, flags: String, mode: Int) -> Result[FileHandle, FileSystemError]
    fn open_directory(path: String) -> Result[Directory, FileSystemError]
    fn copy_tree(source: String, destination: String, replace: Bool = false, max_entries: Optional[Int] = none, max_bytes: Optional[Int64] = none) -> Result[Unit, FileSystemError]
    fn glob(path: String, pattern: String, max_entries: Optional[Int] = none) -> Result[List[String], FileSystemError]
    fn watch(path: String, recursive: Bool, interval: Duration, max_entries: Optional[Int] = none) -> Result[FileWatcher, FileSystemError]
    fn temporary(prefix: String) -> Result[TemporaryDirectory, FileSystemError]
    fn stat_filesystem(path: String) -> Result[FileSystemInfo, FileSystemError]
    fn chmod_link(path: String, mode: Int) -> Result[Unit, FileSystemError]
```

### FileSystem.access

Checks access with mode 0..7: existence 0, read 4, write 2, execute 1, or combined bits.
Native permissions and Windows access policy still apply.

```manuscript
fn access(path: String, mode: Int) -> Result[Unit, FileSystemError]
```

### FileSystem.canonicalize

Resolves symlinks and returns the canonical absolute path.

```manuscript
fn canonicalize(path: String) -> Result[String, FileSystemError]
```

### FileSystem.chmod

Changes target permissions with mode 0..4095; follows a final symbolic link.

```manuscript
fn chmod(path: String, mode: Int) -> Result[Unit, FileSystemError]
```

### FileSystem.chmod_link

Changes the link itself without following it; Unsupported on hosts lacking this operation.

```manuscript
fn chmod_link(path: String, mode: Int) -> Result[Unit, FileSystemError]
```

### FileSystem.copy

Copies a file or tree according to the supplied replacement and size policies.

```manuscript
fn copy(source: String, destination: String, options: CopyOptions, filter: Optional[fn(source: String, destination: String) -> Bool]) -> Result[Unit, FileSystemError]
```

### FileSystem.copy_file

Copies one file; replace defaults to false, refusing an existing destination.

```manuscript
fn copy_file(source: String, destination: String, replace: Bool = false, max_bytes: Optional[Int64] = none) -> Result[Unit, FileSystemError]
```

### FileSystem.copy_tree

Copies a tree; replace defaults to false, refusing existing destinations.
Entry and byte limits remain separate and apply cumulatively across the copy.

```manuscript
fn copy_tree(source: String, destination: String, replace: Bool = false, max_entries: Optional[Int] = none, max_bytes: Optional[Int64] = none) -> Result[Unit, FileSystemError]
```

### FileSystem.create_directory

Creates one directory; recursive defaults to false, requiring its parent to exist.

```manuscript
fn create_directory(path: String, recursive: Bool = false) -> Result[Unit, FileSystemError]
```

### FileSystem.create_link

Creates a symbolic link at `path` pointing to `target`.

```manuscript
fn create_link(path: String, target: String) -> Result[Unit, FileSystemError]
```

### FileSystem.glob_entries

Returns entries matching the supplied include and exclude patterns.

```manuscript
fn glob_entries(path: String, options: GlobOptions, exclude: Optional[fn(entry: PathEntry) -> Bool]) -> Result[List[PathEntry], FileSystemError]
```

### FileSystem.list

Lists a directory, optionally limiting the number of returned entries.

```manuscript
fn list(path: String, max_entries: Optional[Int] = none) -> Result[List[DirectoryEntry], FileSystemError]
```

### FileSystem.open

Opens with exactly r, r+, w, wx, w+, wx+, a, ax, a+, or ax+; other strings return InvalidInput.
Mode is permission bits in 0..4095, applied on creation subject to umask/OS policy.

```manuscript
fn open(path: String, flags: String, mode: Int) -> Result[FileHandle, FileSystemError]
```

### FileSystem.open_flags

Opens a path using host flag bits in 0..2147483647 and permission bits in 0..4095.
Use fs.constants() on this host; unknown bits/combinations are left to the OS.

```manuscript
fn open_flags(path: String, flags: Int64, mode: Int) -> Result[FileHandle, FileSystemError]
```

### FileSystem.read_file

Reads a file fully into memory. Supply `max_bytes` for untrusted or large files.

```manuscript
fn read_file(path: String, max_bytes: Optional[Int64] = none) -> Result[Bytes, FileSystemError]
```

### FileSystem.remove

Removes a file or empty directory; recursive defaults to false, retaining nonempty trees.

```manuscript
fn remove(path: String, recursive: Bool = false) -> Result[Unit, FileSystemError]
```

### FileSystem.temporary

Creates a new temp directory whose contents are removed by scoped close.
Prefix has the same validation as temporary_directory; this does not query the temp root.

```manuscript
fn temporary(prefix: String) -> Result[TemporaryDirectory, FileSystemError]
```

### FileSystem.temporary_directory

Creates a new directory under the host temp root; the caller must remove it.
Prefix must be nonempty and contain no slash, backslash, or NUL.

```manuscript
fn temporary_directory(prefix: String) -> Result[String, FileSystemError]
```

### FileSystem.truncate

Sets the target size in bytes; follows a final symbolic link.

```manuscript
fn truncate(path: String, size: Int64) -> Result[Unit, FileSystemError]
```

### FileSystem.watch_native

Watches native OS events; overflow is exactly `error` or `ignore` (case-sensitive).
Other policies return InvalidInput. Limits bound tracked paths and queued events.

```manuscript
fn watch_native(path: String, recursive: Bool, max_entries: Optional[Int] = none, max_events: Optional[Int] = none, overflow: String) -> Result[FileWatcher, FileSystemError]
```

### FileSystem.write_file

Creates a file exclusively; replace defaults to false, retaining an existing file.

```manuscript
fn write_file(path: String, data: Bytes, replace: Bool = false) -> Result[Unit, FileSystemError]
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

### FileSystemError.NotEmpty

Removal failed because the directory still contains entries.

```manuscript
case NotEmpty
```

## FileSystemInfo {data-api-kind="Record"}

Capacity/free-space statistics: block_size is bytes, blocks/free/available are counts
in those blocks, and files/files_free are native file-node counts (zero if unavailable).

```manuscript
type FileSystemInfo:
    type_id: Int64
    block_size: Int64
    blocks: Int64
    blocks_free: Int64
    blocks_available: Int64
    files: Int64
    files_free: Int64
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

Returns this host's filesystem flag, mode, and permission constants by name.
Names and values vary by host; absent entries are not supported constants or portable enum cases.

```manuscript
fn constants() -> Map[String, Int64]:
```

## filesystem {data-api-kind="Function"}

Returns filesystem operations for the current host.

```manuscript
fn filesystem() -> FileSystem:
```

