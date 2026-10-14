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

### CopyOptions.clone

Exactly `none`, `try`, or `force`; other strings return InvalidInput.
try falls back to byte copying; force requires a native clone operation.

```manuscript
clone: String
```

### CopyOptions.dereference

When true, symbolic links are followed and their targets copied; when false, links are recreated as links.

```manuscript
dereference: Bool
```

### CopyOptions.error_on_exists

When true and `replace` is false, an existing destination file returns AlreadyExists instead of being skipped silently.

```manuscript
error_on_exists: Bool
```

### CopyOptions.max_bytes

Most file bytes copied in total. Exceeding it returns LimitExceeded. none sets no limit.

```manuscript
max_bytes: Optional[Int] = none
```

### CopyOptions.max_entries

Most files, directories, and links visited, counting the root. Exceeding it returns LimitExceeded. none sets no limit.

```manuscript
max_entries: Optional[Int] = none
```

### CopyOptions.preserve_timestamps

When true, copied files and directories keep the source's access and modification times.

```manuscript
preserve_timestamps: Bool
```

### CopyOptions.recursive

When true, directories are copied with their contents; when false, a directory source returns InvalidInput.

```manuscript
recursive: Bool
```

### CopyOptions.replace

When true, an existing destination file or link is replaced; when false, it is kept, or reported when `error_on_exists` is true.

```manuscript
replace: Bool
```

### CopyOptions.verbatim_symlinks

When true, a copied link keeps its target text unchanged. When false, a relative target is rewritten relative to the source directory so it still reaches the original file.

```manuscript
verbatim_symlinks: Bool
```

## Directory {data-api-kind="Interface"}

An open directory that yields one child per read and must be closed.

```manuscript
interface Directory:
    fn path() -> String
    fn close() -> Unit
    fn read() -> Result[Optional[DirectoryEntry], FileSystemError]
```

### Directory.close

Releases the directory handle.
Safe to call repeatedly; later reads return Closed.

```manuscript
fn close() -> Unit
```

### Directory.path

Returns the path this cursor was opened with.

```manuscript
fn path() -> String
```

### Directory.read

Returns the next child in native directory order, or none after the last one.
The order is not sorted.

```manuscript
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

### DirectoryEntry.directory

True when the child is a directory; a symbolic link is reported by `symlink`, not as a directory.

```manuscript
directory: Bool
```

### DirectoryEntry.name

The child's file name only, without any directory part, in the host's spelling.

```manuscript
name: String
```

### DirectoryEntry.symlink

True when the child itself is a symbolic link, whatever it points to.

```manuscript
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

### FileEvent.path

Path of the affected entry, formed from the watched path plus any child components.

```manuscript
path: String
```

## FileHandle {data-api-kind="Interface"}

An open file supporting sequential and positional I/O.

```manuscript
interface FileHandle:
    fn reader() -> ReadStream
    fn writer() -> WriteStream
    fn close() -> Unit
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], FileSystemError]
    fn write(data: Bytes) -> Result[Unit, FileSystemError]
    fn append_file(data: Bytes) -> Result[Unit, FileSystemError]
    fn read_at(offset: Int, max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
    fn write_at(offset: Int, data: Bytes) -> Result[Unit, FileSystemError]
    fn read_file(max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
    fn read_vectors(sizes: List[Int], offset: Int) -> Result[List[Bytes], FileSystemError]
    fn write_vectors(buffers: List[Bytes], offset: Int) -> Result[Unit, FileSystemError]
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

### FileHandle.append_file

Writes at the current position; appends only when the handle was opened in append mode.

```manuscript
fn append_file(data: Bytes) -> Result[Unit, FileSystemError]
```

### FileHandle.chmod

Sets the permission bits of the open file to `mode` (0 through 4095).

```manuscript
fn chmod(mode: Int) -> Result[Unit, FileSystemError]
```

### FileHandle.chown

Sets the owner and group of the open file by numeric id; -1 leaves that id unchanged. Usually needs privilege.

```manuscript
fn chown(uid: Int, gid: Int) -> Result[Unit, FileSystemError]
```

### FileHandle.close

Closes the file, interrupts calls in progress, and waits for them to stop.
Safe to call repeatedly; later operations return Closed.

```manuscript
fn close() -> Unit
```

### FileHandle.data_sync

Flushes the file's data to stable storage, skipping metadata that is not needed to read it back where the host allows.
Hosts without a separate data sync perform a full sync.

```manuscript
fn data_sync() -> Result[Unit, FileSystemError]
```

### FileHandle.read

Returns a positive chunk (at most 64 KiB), or none at EOF; a supplied size must be positive.

```manuscript
fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], FileSystemError]
```

### FileHandle.read_at

Reads at a nonnegative byte offset without moving the position; short/empty Bytes mark EOF.

```manuscript
fn read_at(offset: Int, max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
```

### FileHandle.read_file

Reads remaining bytes from the current position; EOF returns empty Bytes.

```manuscript
fn read_file(max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
```

### FileHandle.read_lines

Reads from the current position to the end and returns the lines with their `\n` or `\r\n` terminators removed.
Invalid UTF-8 returns InvalidData, and more bytes than `max_bytes` or lines than `max_lines` returns LimitExceeded.

```manuscript
fn read_lines(max_bytes: Optional[Int] = none, max_lines: Optional[Int] = none) -> Result[List[String], FileSystemError]
```

### FileHandle.read_vectors

Reads consecutive buffers of the given `sizes` in bytes, each up to 65536 and all together up to 16 MiB, and returns the bytes obtained for each.
`offset` -1 reads from the current position; other offsets read without moving it. A buffer is shorter than requested at end of file. A negative size or offset below -1 returns InvalidInput.

```manuscript
fn read_vectors(sizes: List[Int], offset: Int) -> Result[List[Bytes], FileSystemError]
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
fn seek(offset: Int, origin: Int) -> Result[Int, FileSystemError]
```

### FileHandle.set_times

Sets the access and modification times of the open file. Returns Unsupported on hosts without descriptor timestamps.

```manuscript
fn set_times(accessed: Timestamp, modified: Timestamp) -> Result[Unit, FileSystemError]
```

### FileHandle.stat

Returns metadata for the open file.

```manuscript
fn stat() -> Result[FileInfo, FileSystemError]
```

### FileHandle.sync

Flushes the file's data and metadata to stable storage.

```manuscript
fn sync() -> Result[Unit, FileSystemError]
```

### FileHandle.truncate

Sets the file length to `size` bytes, discarding the excess or extending with zero bytes. The current position is not moved.
A negative size returns InvalidInput.

```manuscript
fn truncate(size: Int) -> Result[Unit, FileSystemError]
```

### FileHandle.write

Writes all bytes at the current position; errors can leave a prefix. Does not truncate or reposition this handle.

```manuscript
fn write(data: Bytes) -> Result[Unit, FileSystemError]
```

### FileHandle.write_at

Writes all bytes at a nonnegative offset without moving the position; errors can leave a prefix.

```manuscript
fn write_at(offset: Int, data: Bytes) -> Result[Unit, FileSystemError]
```

### FileHandle.write_vectors

Writes every buffer; offset -1 uses the current position.

```manuscript
fn write_vectors(buffers: List[Bytes], offset: Int) -> Result[Unit, FileSystemError]
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

### FileInfo.accessed

Time the file was last read; it falls back to `modified` where the host lacks access times.

```manuscript
accessed: Timestamp
```

### FileInfo.block_device

True for a block special device.

```manuscript
block_device: Bool
```

### FileInfo.block_size

Preferred I/O block size in bytes; unavailable fields are zero.

```manuscript
block_size: Int
```

### FileInfo.blocks

Allocated 512-byte blocks on POSIX hosts; unavailable fields are zero.

```manuscript
blocks: Int
```

### FileInfo.changed

Time the file's metadata or contents last changed; it falls back to `modified` where the host lacks it.

```manuscript
changed: Timestamp
```

### FileInfo.char_device

True for a character special device.

```manuscript
char_device: Bool
```

### FileInfo.created

Birth time of the file, or none when the host or filesystem does not record it.

```manuscript
created: Optional[Timestamp]
```

### FileInfo.device

Id of the device that holds the file; with `inode` it identifies the file. 0 where unavailable.

```manuscript
device: Int
```

### FileInfo.directory

True when the entry is a directory.

```manuscript
directory: Bool
```

### FileInfo.exact

Unbounded copies of the numeric fields `size`, `mode`, `device`, `inode`, `links`, `uid`, `gid`, `block_size`, `blocks`, and `rdev`, which cannot overflow, plus the times as nanoseconds since the Unix epoch under `accessed_ns`, `modified_ns`, `changed_ns`, and `created_ns`.
Unavailable values are 0.

```manuscript
exact: Map[String, BigInt]
```

### FileInfo.fifo

True for a named pipe.

```manuscript
fifo: Bool
```

### FileInfo.gid

Numeric id of the owning group; 0 where unavailable.

```manuscript
gid: Int
```

### FileInfo.inode

The file's index number on its device; 0 where unavailable.

```manuscript
inode: Int
```

### FileInfo.links

Number of hard links to the file; 0 where unavailable.

```manuscript
links: Int
```

### FileInfo.mode

POSIX mode bits: the file-type bits such as 0100000 for a regular file, plus permission and setuid, setgid, and sticky bits.

```manuscript
mode: Int
```

### FileInfo.modified

Time the file's contents were last changed.

```manuscript
modified: Timestamp
```

### FileInfo.name

The final path component's file name only.

```manuscript
name: String
```

### FileInfo.permissions

Only the permission, setuid, setgid, and sticky bits of `mode`, 0 through 4095.

```manuscript
permissions: Int
```

### FileInfo.rdev

Device id the entry represents when it is a device file, otherwise 0.

```manuscript
rdev: Int
```

### FileInfo.regular

True for an ordinary file, as opposed to a directory, link, or special file.

```manuscript
regular: Bool
```

### FileInfo.size

File length in bytes.

```manuscript
size: Int
```

### FileInfo.socket

True for a Unix domain socket file.

```manuscript
socket: Bool
```

### FileInfo.symlink

True when the entry is itself a symbolic link, which only happens when links were not followed.

```manuscript
symlink: Bool
```

### FileInfo.uid

Numeric id of the owning user; 0 where unavailable.

```manuscript
uid: Int
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
    fn copy_file(source: String, destination: String, replace: Bool = false, max_bytes: Optional[Int] = none) -> Result[Unit, FileSystemError]
    fn create_directory(path: String, recursive: Bool = false) -> Result[Unit, FileSystemError]
    fn create_link(path: String, target: String) -> Result[Unit, FileSystemError]
    fn list(path: String, max_entries: Optional[Int] = none) -> Result[List[DirectoryEntry], FileSystemError]
    fn read_file(path: String, max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
    fn read_link(path: String) -> Result[String, FileSystemError]
    fn remove(path: String, recursive: Bool = false) -> Result[Unit, FileSystemError]
    fn rename(source: String, destination: String) -> Result[Unit, FileSystemError]
    fn stat(path: String, follow_links: Bool) -> Result[FileInfo, FileSystemError]
    fn temporary_directory(prefix: String) -> Result[String, FileSystemError]
    fn write_file(path: String, data: Bytes, replace: Bool = false) -> Result[Unit, FileSystemError]
    fn access(path: String, mode: Int) -> Result[Unit, FileSystemError]
    fn append_file(path: String, data: Bytes) -> Result[Unit, FileSystemError]
    fn chmod(path: String, mode: Int) -> Result[Unit, FileSystemError]
    fn chown(path: String, uid: Int, gid: Int, follow_links: Bool) -> Result[Unit, FileSystemError]
    fn truncate(path: String, size: Int) -> Result[Unit, FileSystemError]
    fn set_times(path: String, accessed: Timestamp, modified: Timestamp, follow_links: Bool) -> Result[Unit, FileSystemError]
    fn hard_link(source: String, destination: String) -> Result[Unit, FileSystemError]
    fn open(path: String, flags: String, mode: Int) -> Result[FileHandle, FileSystemError]
    fn open_directory(path: String) -> Result[Directory, FileSystemError]
    fn copy_tree(source: String, destination: String, replace: Bool = false, max_entries: Optional[Int] = none, max_bytes: Optional[Int] = none) -> Result[Unit, FileSystemError]
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

### FileSystem.append_file

Appends `data` to the end of the file, creating it with mode 0600 when absent. Writes every byte or fails, possibly leaving a partial append.

```manuscript
fn append_file(path: String, data: Bytes) -> Result[Unit, FileSystemError]
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

### FileSystem.chown

Sets the owning user and group of `path` by numeric id; -1 leaves that id unchanged.
`follow_links` chooses the link target (true) or the link itself (false). Usually needs privilege, and Windows returns Unsupported.

```manuscript
fn chown(path: String, uid: Int, gid: Int, follow_links: Bool) -> Result[Unit, FileSystemError]
```

### FileSystem.copy

Copies a file or tree according to the supplied replacement and size policies.

```manuscript
fn copy(source: String, destination: String, options: CopyOptions, filter: Optional[fn(source: String, destination: String) -> Bool]) -> Result[Unit, FileSystemError]
```

### FileSystem.copy_file

Copies one file; replace defaults to false, refusing an existing destination.

```manuscript
fn copy_file(source: String, destination: String, replace: Bool = false, max_bytes: Optional[Int] = none) -> Result[Unit, FileSystemError]
```

### FileSystem.copy_tree

Copies a tree; replace defaults to false, refusing existing destinations.
Entry and byte limits remain separate and apply cumulatively across the copy.

```manuscript
fn copy_tree(source: String, destination: String, replace: Bool = false, max_entries: Optional[Int] = none, max_bytes: Optional[Int] = none) -> Result[Unit, FileSystemError]
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

### FileSystem.glob

Returns the sorted relative paths under `path` matching `pattern`, without following directory symlinks.
A malformed pattern, or one over 4096 bytes, or a negative `max_entries` returns InvalidInput. Matches beyond `max_entries` return LimitExceeded.

```manuscript
fn glob(path: String, pattern: String, max_entries: Optional[Int] = none) -> Result[List[String], FileSystemError]
```

### FileSystem.glob_entries

Returns entries matching the supplied include and exclude patterns.

```manuscript
fn glob_entries(path: String, options: GlobOptions, exclude: Optional[fn(entry: PathEntry) -> Bool]) -> Result[List[PathEntry], FileSystemError]
```

### FileSystem.hard_link

Creates `destination` as another name for the file at `source`.
An existing destination returns AlreadyExists; it must be on the same filesystem as `source`.

```manuscript
fn hard_link(source: String, destination: String) -> Result[Unit, FileSystemError]
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

### FileSystem.open_directory

Opens `path` as a directory cursor that yields one child per `read` in native order; close it when done.
A path that is not a directory returns InvalidInput.

```manuscript
fn open_directory(path: String) -> Result[Directory, FileSystemError]
```

### FileSystem.open_flags

Opens a path using host flag bits in 0..2147483647 and permission bits in 0..4095.
Use fs.constants() on this host; unknown bits/combinations are left to the OS.

```manuscript
fn open_flags(path: String, flags: Int, mode: Int) -> Result[FileHandle, FileSystemError]
```

### FileSystem.read_file

Reads a file fully into memory. Supply `max_bytes` for untrusted or large files.

```manuscript
fn read_file(path: String, max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
```

### FileSystem.read_link

Returns the target text stored in the symbolic link at `path`, without resolving it.
A path that is not a link returns InvalidInput.

```manuscript
fn read_link(path: String) -> Result[String, FileSystemError]
```

### FileSystem.remove

Removes a file or empty directory; recursive defaults to false, retaining nonempty trees.

```manuscript
fn remove(path: String, recursive: Bool = false) -> Result[Unit, FileSystemError]
```

### FileSystem.rename

Moves `source` to `destination` using the operating system's rename, applying its rules for replacing an existing destination.
It never falls back to copying, so a move across devices returns an error.

```manuscript
fn rename(source: String, destination: String) -> Result[Unit, FileSystemError]
```

### FileSystem.set_times

Sets the access and modification times of `path`.
`follow_links` chooses the link target (true) or the link itself (false); no-follow updates return Unsupported where the host lacks them, such as Windows.

```manuscript
fn set_times(path: String, accessed: Timestamp, modified: Timestamp, follow_links: Bool) -> Result[Unit, FileSystemError]
```

### FileSystem.stat

Returns metadata for `path`. `follow_links` true describes the link target and false describes the link itself.

```manuscript
fn stat(path: String, follow_links: Bool) -> Result[FileInfo, FileSystemError]
```

### FileSystem.stat_filesystem

Returns capacity and free-space statistics for the filesystem containing `path`.
Hosts without the query return Unsupported.

```manuscript
fn stat_filesystem(path: String) -> Result[FileSystemInfo, FileSystemError]
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
fn truncate(path: String, size: Int) -> Result[Unit, FileSystemError]
```

### FileSystem.watch

Returns a polling watcher that compares snapshots of `path` every `interval`, which must be positive.
`max_entries` bounds the tracked paths; exceeding it returns LimitExceeded. Transient changes between polls can be missed.

```manuscript
fn watch(path: String, recursive: Bool, interval: Duration, max_entries: Optional[Int] = none) -> Result[FileWatcher, FileSystemError]
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

### FileSystemError.AlreadyExists

The destination exists and the operation refuses to replace it, such as exclusive creation with `replace: false`.

```manuscript
case AlreadyExists
```

### FileSystemError.Closed

The file, directory, or watcher was already closed.

```manuscript
case Closed
```

### FileSystemError.Failed

The host reported an unexpected failure not covered by another case.

```manuscript
case Failed(message: String)
```

### FileSystemError.InvalidData

File content could not be interpreted, such as invalid UTF-8 text in `read_lines`.

```manuscript
case InvalidData
```

### FileSystemError.InvalidInput

A path is empty or holds NUL, an argument is outside its range (mode bits, offset, size, flags string, origin), the handle lacks the needed read or write mode, or the operation targets the wrong kind of entry.

```manuscript
case InvalidInput
```

### FileSystemError.LimitExceeded

A byte, line, or entry budget such as `max_bytes` or `max_entries` was exceeded, rather than returning a truncated result.

```manuscript
case LimitExceeded
```

### FileSystemError.NotEmpty

Removal failed because the directory still contains entries.

```manuscript
case NotEmpty
```

### FileSystemError.NotFound

The path, or a parent directory it needs, does not exist.

```manuscript
case NotFound
```

### FileSystemError.PermissionDenied

The operating system refused access to the path or operation.

```manuscript
case PermissionDenied
```

### FileSystemError.Unsupported

The host or filesystem cannot perform the operation, or a file name is not valid UTF-8.

```manuscript
case Unsupported
```

### FileSystemError.Failed.message

Host-provided failure text; `message()` returns it verbatim, so it can name paths.

```manuscript
message: String
```

### FileSystemError.Error.message

Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `filesystem: <reason>`, such as `filesystem: file or directory not found`.

```manuscript
fn message() -> String:
```

## FileSystemInfo {data-api-kind="Record"}

Capacity/free-space statistics: block_size is bytes, blocks/free/available are counts
in those blocks, and files/files_free are native file-node counts (zero if unavailable).

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

### FileSystemInfo.block_size

Size in bytes of the blocks that `blocks`, `blocks_free`, and `blocks_available` count.

```manuscript
block_size: Int
```

### FileSystemInfo.blocks

Total number of blocks in the filesystem.

```manuscript
blocks: Int
```

### FileSystemInfo.blocks_available

Number of unused blocks available to unprivileged users.

```manuscript
blocks_available: Int
```

### FileSystemInfo.blocks_free

Number of unused blocks, including space reserved for privileged users.

```manuscript
blocks_free: Int
```

### FileSystemInfo.files

Total number of file nodes, such as inodes, the filesystem can hold; 0 where unavailable.

```manuscript
files: Int
```

### FileSystemInfo.files_free

Number of unused file nodes; 0 where unavailable.

```manuscript
files_free: Int
```

### FileSystemInfo.type_id

The host's numeric filesystem type code, such as the magic number reported by Linux; 0 where unavailable.

```manuscript
type_id: Int
```

## FileWatcher {data-api-kind="Interface"}

A change stream returned by a filesystem watch operation.

```manuscript
interface FileWatcher:
    fn close() -> Unit
    fn next() -> Result[List[FileEvent], FileSystemError]
```

### FileWatcher.close

Stops the watcher, wakes a pending `next` with Closed, and waits for its worker to stop.
Safe to call repeatedly.

```manuscript
fn close() -> Unit
```

### FileWatcher.next

Waits for filesystem activity and returns events. A native watcher returns one event per call; a polling watcher returns every difference seen after an interval.
Cancelling the waiting task unwinds it, and a closed watcher returns Closed. A native watcher that overflowed with policy `error` returns LimitExceeded.

```manuscript
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

### GlobOptions.exclude

Glob patterns for entries to skip; a match is neither returned nor searched further.

```manuscript
exclude: List[String]
```

### GlobOptions.follow_links

When true, symbolic links to directories are traversed, with cycles detected; when false, links are reported but not entered.

```manuscript
follow_links: Bool
```

### GlobOptions.max_entries

Most filesystem entries visited while searching. Exceeding it returns LimitExceeded. none sets no limit.

```manuscript
max_entries: Optional[Int] = none
```

### GlobOptions.max_results

Most distinct matches returned. Exceeding it returns LimitExceeded. none sets no limit.

```manuscript
max_results: Optional[Int] = none
```

### GlobOptions.patterns

Glob patterns to include; an entry that matches any of them is returned.

```manuscript
patterns: List[String]
```

## PathEntry {data-api-kind="Record"}

A matched path together with its filesystem entry metadata.

```manuscript
type PathEntry:
    path: String
    entry: DirectoryEntry
```

### PathEntry.entry

The directory entry record for the match: name, directory flag, and symlink flag.

```manuscript
entry: DirectoryEntry
```

### PathEntry.path

The matched path relative to the glob root, using the host's separators.

```manuscript
path: String
```

## TemporaryDirectory {data-api-kind="Interface"}

A temporary directory whose contents are removed when it is closed.

```manuscript
interface TemporaryDirectory:
    fn close() -> Unit
    fn path() -> String
```

### TemporaryDirectory.close

Removes the directory and everything inside it.
Safe to call repeatedly.

```manuscript
fn close() -> Unit
```

### TemporaryDirectory.path

Returns the absolute path of the directory, created under the host's temporary root.

```manuscript
fn path() -> String
```

## constants {data-api-kind="Function"}

Returns this host's filesystem flag, mode, and permission constants by name.
Names and values vary by host; absent entries are not supported constants or portable enum cases.

```manuscript
fn constants() -> Map[String, Int]:
```

## filesystem {data-api-kind="Function"}

Returns filesystem operations for the current host.

```manuscript
fn filesystem() -> FileSystem:
```

