import BigInt from "@std/math.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import ReadStream from "@std/io.ms"
import Timestamp from "@std/time.ms"
import WriteStream from "@std/io.ms"
import Closeable from "@std/core.ms"

extern fn msstd_fs_constants() Map[String, Int]

extern fn msstd_fs_filesystem() FileSystem

extern fn msrt_path_basename(path: String) String

extern fn msrt_path_dirname(path: String) String

extern fn msrt_path_extension(path: String) String

extern fn msrt_path_is_absolute(path: String) Bool

extern fn msrt_path_join(parts: List[String]) String

extern fn msrt_path_normalize(path: String) String

extern fn msrt_path_relative(base: String, target: String) String!PathError

extern fn msstd_fs_posix() PathOperations

extern fn msstd_fs_win32() PathOperations

extern fn msrt_path_basename_without(path: String, suffix: String) String

extern fn msrt_path_resolve(base: String, parts: List[String]) String!PathError

extern fn msrt_path_parse(path: String) PathParts

extern fn msrt_path_format(parts: PathParts) String

extern fn msrt_path_separator() String

extern fn msrt_path_delimiter() String

extern fn msrt_path_to_namespaced_path(path: String) String

extern fn msrt_path_matches_glob(path: String, pattern: String) Bool!PathError

# Errors returned by filesystem operations. `Failed` retains the host error text.
export type FileSystemError:
    # A path is empty or holds NUL, an argument is outside its range (mode bits, offset, size, flags string, origin), the handle lacks the needed read or write mode, or the operation targets the wrong kind of entry.
    case InvalidInput
    # File content could not be interpreted, such as invalid UTF-8 text in `read_lines`.
    case InvalidData
    # A byte, line, or entry budget such as `max_bytes` or `max_entries` was exceeded, rather than returning a truncated result.
    case LimitExceeded
    # The path, or a parent directory it needs, does not exist.
    case NotFound
    # The destination exists and the operation refuses to replace it, such as exclusive creation with `replace: False`.
    case AlreadyExists
    # Removal failed because the directory still contains entries.
    case NotEmpty
    # The operating system refused access to the path or operation.
    case PermissionDenied
    # The host or filesystem cannot perform the operation, or a link target or canonical path is not valid UTF-8.
    case Unsupported
    # The file, directory, or watcher was already closed.
    case Closed
    # The host reported an unexpected failure not covered by another case.
    case Failed(
        # Host-provided failure text; `message()` returns it verbatim, so it can name paths.
        message: String
    )

# The name and kind flags for one child returned by a directory listing.
export type DirectoryEntry:
    # The child's file name only, without any directory part, in the host's spelling.
    name: String
    # True when the child is a directory; a symbolic link is reported by `symlink`, not as a directory.
    directory: Bool
    # True when the child itself is a symbolic link, whatever it points to.
    symlink: Bool

# File metadata, including portable fields and exact platform-specific numeric values.
export type FileInfo:
    # The final path component's file name only.
    name: String
    # File length in bytes.
    size: Int
    # True when the entry is a directory.
    directory: Bool
    # True when the entry is itself a symbolic link, which only happens when links were not followed.
    symlink: Bool
    # Time the file's contents were last changed.
    modified: Timestamp
    # Time the file was last read; it falls back to `modified` where the host lacks access times.
    accessed: Timestamp
    # Time the file's metadata or contents last changed; it falls back to `modified` where the host lacks it.
    changed: Timestamp
    # POSIX mode bits: the file-type bits such as 0100000 for a regular file, plus permission and setuid, setgid, and sticky bits.
    mode: Int
    # Only the permission, setuid, setgid, and sticky bits of `mode`, 0 through 4095.
    permissions: Int
    # Birth time of the file, or none when the host or filesystem does not record it.
    created: Timestamp?
    # Preferred I/O block size in bytes; unavailable fields are zero.
    block_size: Int
    # Allocated 512-byte blocks on POSIX hosts; unavailable fields are zero.
    blocks: Int
    # Device id the entry represents when it is a device file, otherwise 0.
    rdev: Int
    # True for a named pipe.
    fifo: Bool
    # True for a Unix domain socket file.
    socket: Bool
    # True for a block special device.
    block_device: Bool
    # True for a character special device.
    char_device: Bool
    # Unbounded copies of the numeric fields `size`, `mode`, `device`, `inode`, `links`, `uid`, `gid`, `block_size`, `blocks`, and `rdev`, which cannot overflow, plus the times as nanoseconds since the Unix epoch under `accessed_ns`, `modified_ns`, `changed_ns`, and `created_ns`.
    # Unavailable values are 0.
    exact: Map[String, BigInt]
    # True for an ordinary file, as opposed to a directory, link, or special file.
    regular: Bool
    # Id of the device that holds the file; with `inode` it identifies the file. 0 where unavailable.
    device: Int
    # The file's index number on its device; 0 where unavailable.
    inode: Int
    # Number of hard links to the file; 0 where unavailable.
    links: Int
    # Numeric id of the owning user; 0 where unavailable.
    uid: Int
    # Numeric id of the owning group; 0 where unavailable.
    gid: Int

# Filesystem operations and resource factories for the current host.
export interface FileSystem:
    # Opens a path using host flag bits in 0..2147483647 and permission bits in 0..4095.
    # Use fs.constants() on this host; unknown bits/combinations are left to the OS.
    fn open_flags(path: String, flags: Int, mode: Int) FileHandle!FileSystemError
    # Returns entries matching the supplied include and exclude patterns.
    fn glob_entries(
        path: String,
        options: GlobOptions,
        exclude: (fn(PathEntry) Bool)?
    ) List[PathEntry]!FileSystemError
    # Copies a file or tree according to the supplied replacement and size policies.
    fn copy(
        source: String,
        destination: String,
        options: CopyOptions,
        filter: (fn(String, String) Bool)?
    ) Unit!FileSystemError
    # Watches native OS events (inotify on Linux, kqueue on macOS, ReadDirectoryChangesW on Windows); overflow is exactly `error` or `ignore` (case-sensitive).
    # Other policies return InvalidInput. `max_entries` bounds the paths under the root (the root, files and directories), counted when the watcher starts and failing with LimitExceeded, the same on every platform; `max_events` bounds queued events.
    fn watch_native(
        path: String,
        recursive: Bool,
        max_entries: Int?,
        max_events: Int?,
        overflow: String
    ) FileWatcher!FileSystemError
    # Resolves symlinks and returns the canonical absolute path.
    fn canonicalize(path: String) String!FileSystemError
    # Copies one file; replace defaults to False, refusing an existing destination.
    fn copy_file(
        source: String,
        destination: String,
        replace: Bool = false,
        max_bytes: Int?
    ) Unit!FileSystemError
    # Creates one directory; recursive defaults to False, requiring its parent to exist.
    fn create_directory(path: String, recursive: Bool = false) Unit!FileSystemError
    # Creates a symbolic link at `path` pointing to `target`.
    fn create_link(path: String, target: String) Unit!FileSystemError
    # Lists a directory, optionally limiting the number of returned entries.
    # A name that is not valid UTF-8 is listed with U+FFFD in place of each invalid byte, so it no longer addresses the entry. The same holds for `glob`, `glob_entries`, `stat` names and directory cursors.
    fn list(path: String, max_entries: Int?) List[DirectoryEntry]!FileSystemError
    # Reads a file fully into memory. Supply `max_bytes` for untrusted or large files.
    fn read_file(path: String, max_bytes: Int?) Bytes!FileSystemError
    # Returns the target text stored in the symbolic link at `path`, without resolving it.
    # A path that is not a link returns InvalidInput.
    fn read_link(path: String) String!FileSystemError
    # Removes a file or empty directory; recursive defaults to False, retaining nonempty trees.
    # A missing path returns NotFound, except that a recursive removal of a missing path succeeds.
    fn remove(path: String, recursive: Bool = false) Unit!FileSystemError
    # Moves `source` to `destination` using the operating system's rename, applying its rules for replacing an existing destination.
    # It never falls back to copying, so a move across devices returns an error.
    fn rename(source: String, destination: String) Unit!FileSystemError
    # Returns metadata for `path`. `follow_links` True describes the link target and False describes the link itself.
    fn stat(path: String, follow_links: Bool) FileInfo!FileSystemError
    # Queries the host temp root without creating or checking a directory.
    fn temporary_root() String!FileSystemError
    # Creates a new directory under the host temp root; the caller must remove it.
    # Prefix must be nonempty and contain no slash, backslash, or NUL.
    fn temporary_directory(prefix: String) String!FileSystemError
    # Creates a file exclusively; replace defaults to False, retaining an existing file.
    fn write_file(
        path: String,
        data: String,
        replace: Bool = false
    ) Unit!FileSystemError
    # Creates a file exclusively from raw bytes; replace defaults to False, retaining an existing file.
    fn write_file_bytes(
        path: String,
        data: Bytes,
        replace: Bool = false
    ) Unit!FileSystemError
    # Checks access with mode 0..7: existence 0, read 4, write 2, execute 1, or combined bits.
    # Native permissions and Windows access policy still apply.
    fn access(path: String, mode: Int) Unit!FileSystemError
    # Appends `data` to the end of the file, creating it with mode 0600 when absent. Writes every byte or fails, possibly leaving a partial append.
    fn append_file(path: String, data: String) Unit!FileSystemError
    # Appends raw bytes to the end of the file, with the same creation and partial-write rules as append_file.
    fn append_file_bytes(path: String, data: Bytes) Unit!FileSystemError
    # Changes target permissions with mode 0..4095; follows a final symbolic link.
    fn chmod(path: String, mode: Int) Unit!FileSystemError
    # Sets the owning user and group of `path` by numeric id; -1 leaves that id unchanged.
    # `follow_links` chooses the link target (True) or the link itself (False). Usually needs privilege, and Windows returns Unsupported.
    fn chown(path: String, uid: Int, gid: Int, follow_links: Bool) Unit!FileSystemError
    # Sets the target size in bytes; follows a final symbolic link.
    fn truncate(path: String, size: Int) Unit!FileSystemError
    # Sets the access and modification times of `path`.
    # `follow_links` chooses the link target (True) or the link itself (False); no-follow updates return Unsupported where the host lacks them, such as Windows.
    fn set_times(
        path: String,
        accessed: Timestamp,
        modified: Timestamp,
        follow_links: Bool
    ) Unit!FileSystemError
    # Creates `destination` as another name for the file at `source`.
    # An existing destination returns AlreadyExists; it must be on the same filesystem as `source`.
    fn hard_link(source: String, destination: String) Unit!FileSystemError
    # Opens with exactly r, r+, w, wx, w+, wx+, a, ax, a+, or ax+; other strings return InvalidInput.
    # Mode is permission bits in 0..4095, applied on creation subject to umask/OS policy.
    fn open(path: String, flags: String, mode: Int) FileHandle!FileSystemError
    # Opens `path` as a directory cursor that yields one child per `read` in native order; close it when done.
    # A path that is not a directory returns InvalidInput.
    fn open_directory(path: String) Directory!FileSystemError
    # Copies a tree; replace defaults to False, refusing existing destinations.
    # Entry and byte limits remain separate and apply cumulatively across the copy.
    fn copy_tree(
        source: String,
        destination: String,
        replace: Bool = false,
        max_entries: Int?,
        max_bytes: Int?
    ) Unit!FileSystemError
    # Returns the sorted relative paths under `path` matching `pattern`, without following directory symlinks.
    # A malformed pattern, or one over 4096 bytes, or a negative `max_entries` returns InvalidInput. Matches beyond `max_entries` return LimitExceeded.
    fn glob(
        path: String,
        pattern: String,
        max_entries: Int?
    ) List[String]!FileSystemError
    # Returns a polling watcher that compares snapshots of `path` every `interval`, which must be positive.
    # `max_entries` bounds the tracked paths; exceeding it returns LimitExceeded. Transient changes between polls can be missed.
    fn watch(
        path: String,
        recursive: Bool,
        interval: Duration,
        max_entries: Int?
    ) FileWatcher!FileSystemError
    # Creates a new temp directory whose contents are removed by scoped close.
    # Prefix has the same validation as temporary_directory; this does not query the temp root.
    fn temporary(prefix: String) TemporaryDirectory!FileSystemError
    # Returns capacity and free-space statistics for the filesystem containing `path`.
    # Hosts without the query return Unsupported.
    fn stat_filesystem(path: String) FileSystemInfo!FileSystemError
    # Changes the link itself without following it; Unsupported on hosts lacking this operation.
    fn chmod_link(path: String, mode: Int) Unit!FileSystemError

# The runtime handle behind a `FileHandle`.
export extern type NativeFile

extern fn msstd_fs_file_reader(file: NativeFile) ReadStream

extern fn msstd_fs_file_writer(file: NativeFile) WriteStream

extern fn msstd_io_close(file: NativeFile) Unit

extern fn msstd_fs_file_clone(file: NativeFile) FileHandle!FileSystemError

extern fn msstd_io_read(file: NativeFile, max_bytes: Int?) Bytes?!FileSystemError

extern fn msstd_io_write(file: NativeFile, data: String) Unit!FileSystemError

extern fn msstd_io_write_bytes(file: NativeFile, data: Bytes) Unit!FileSystemError

extern fn msstd_fs_file_read_at(
    file: NativeFile,
    offset: Int,
    max_bytes: Int?
) Bytes!FileSystemError

extern fn msstd_fs_file_write_at(
    file: NativeFile,
    offset: Int,
    data: Bytes
) Unit!FileSystemError

extern fn msstd_fs_file_read_file(
    file: NativeFile,
    max_bytes: Int?
) Bytes!FileSystemError

extern fn msstd_fs_file_read_vectors(
    file: NativeFile,
    sizes: List[Int],
    offset: Int
) List[Bytes]!FileSystemError

extern fn msstd_fs_file_write_vectors(
    file: NativeFile,
    buffers: List[Bytes],
    offset: Int
) Unit!FileSystemError

extern fn msstd_fs_file_seek(
    file: NativeFile,
    offset: Int,
    origin: Int
) Int!FileSystemError

extern fn msstd_fs_file_stat(file: NativeFile) FileInfo!FileSystemError

extern fn msstd_fs_file_truncate(file: NativeFile, size: Int) Unit!FileSystemError

extern fn msstd_fs_file_sync(file: NativeFile) Unit!FileSystemError

extern fn msstd_fs_file_data_sync(file: NativeFile) Unit!FileSystemError

extern fn msstd_fs_file_chmod(file: NativeFile, mode: Int) Unit!FileSystemError

extern fn msstd_fs_file_chown(file: NativeFile, uid: Int, gid: Int) Unit!FileSystemError

extern fn msstd_fs_file_set_times(
    file: NativeFile,
    accessed: Timestamp,
    modified: Timestamp
) Unit!FileSystemError

extern fn msstd_fs_file_read_lines(
    file: NativeFile,
    max_bytes: Int?,
    max_lines: Int?
) List[String]!FileSystemError

# An open file supporting sequential and positional I/O. It owns its descriptor: `close` it, or let
# its binding go out of scope.
export type FileHandle:
    # The runtime handle for the open file; it is released by `close` and owned by this value.
    native: NativeFile

impl Closeable for FileHandle:
    # Closes the file, interrupts calls in progress, and waits for them to stop.
    # Safe to call repeatedly; later operations return Closed.
    var fn close() Unit!:
        msstd_io_close(self.native)
        return ok(unit)

impl FileHandle:
    # Returns a second handle over a duplicate of the file's descriptor, which closes on its own.
    # Both share the file position, so a read or write through one moves the other; bytes this handle already read ahead stay with it.
    # A closed handle returns Closed.
    fn clone() FileHandle!FileSystemError:
        return msstd_fs_file_clone(self.native)

    # Adapts this handle to IoError/Optional chunk reads; closing either view closes all aliases.
    fn reader() ReadStream:
        return msstd_fs_file_reader(self.native)

    # Adapts complete writes to IoError/Unit; flush synchronizes the file.
    fn writer() WriteStream:
        return msstd_fs_file_writer(self.native)

    # Returns a positive chunk (at most 64 KiB), or none at EOF; a supplied size must be positive.
    fn read(max_bytes: Int?) Bytes?!FileSystemError:
        return msstd_io_read(self.native, max_bytes)

    # Writes the UTF-8 text at the current position; errors can leave a prefix. Does not truncate or reposition this handle.
    fn write(data: String) Unit!FileSystemError:
        return msstd_io_write(self.native, data)

    # Writes all bytes at the current position, with the same rules as write.
    fn write_bytes(data: Bytes) Unit!FileSystemError:
        return msstd_io_write_bytes(self.native, data)

    # Writes text at the current position; appends only when the handle was opened in append mode.
    fn append_file(data: String) Unit!FileSystemError:
        return msstd_io_write(self.native, data)

    # Writes bytes at the current position; appends only when the handle was opened in append mode.
    fn append_file_bytes(data: Bytes) Unit!FileSystemError:
        return msstd_io_write_bytes(self.native, data)

    # Reads at a nonnegative byte offset without moving the position; short/empty Bytes mark EOF.
    fn read_at(offset: Int, max_bytes: Int?) Bytes!FileSystemError:
        return msstd_fs_file_read_at(self.native, offset, max_bytes)

    # Writes the UTF-8 text at a nonnegative offset without moving the position; a handle opened for append returns InvalidInput because the host would ignore the offset; errors can leave a prefix.
    fn write_at(offset: Int, data: String) Unit!FileSystemError:
        return msstd_fs_file_write_at(self.native, offset, data.to_bytes())

    # Writes all bytes at a nonnegative offset without moving the position; a handle opened for append returns InvalidInput because the host would ignore the offset; errors can leave a prefix.
    fn write_at_bytes(offset: Int, data: Bytes) Unit!FileSystemError:
        return msstd_fs_file_write_at(self.native, offset, data)

    # Reads remaining bytes from the current position; EOF returns empty Bytes.
    fn read_file(max_bytes: Int?) Bytes!FileSystemError:
        return msstd_fs_file_read_file(self.native, max_bytes)

    # Reads consecutive buffers of the given `sizes` in bytes, each up to 65536 and all together up to 16 MiB, and returns the bytes obtained for each.
    # `offset` -1 reads from the current position; other offsets read without moving it. A buffer is shorter than requested at end of file. A negative size or offset below -1 returns InvalidInput.
    fn read_vectors(sizes: List[Int], offset: Int) List[Bytes]!FileSystemError:
        return msstd_fs_file_read_vectors(self.native, sizes, offset)

    # Writes every buffer; offset -1 uses the current position. A nonnegative offset on a handle opened for append returns InvalidInput.
    fn write_vectors(buffers: List[Bytes], offset: Int) Unit!FileSystemError:
        return msstd_fs_file_write_vectors(self.native, buffers, offset)

    # Seeks in bytes with origin exactly 0 (start), 1 (current), or 2 (end).
    # Other origins return InvalidInput; the OS validates the resulting offset.
    fn seek(offset: Int, origin: Int) Int!FileSystemError:
        return msstd_fs_file_seek(self.native, offset, origin)

    # Returns metadata for the open file.
    fn stat() FileInfo!FileSystemError:
        return msstd_fs_file_stat(self.native)

    # Sets the file length to `size` bytes, discarding the excess or extending with zero bytes. The current position is not moved.
    # A negative size returns InvalidInput.
    fn truncate(size: Int) Unit!FileSystemError:
        return msstd_fs_file_truncate(self.native, size)

    # Flushes the file's data and metadata to stable storage.
    fn sync() Unit!FileSystemError:
        return msstd_fs_file_sync(self.native)

    # Flushes the file's data to stable storage, skipping metadata that is not needed to read it back where the host allows.
    # Hosts without a separate data sync perform a full sync.
    fn data_sync() Unit!FileSystemError:
        return msstd_fs_file_data_sync(self.native)

    # Sets the permission bits of the open file to `mode` (0 through 4095).
    fn chmod(mode: Int) Unit!FileSystemError:
        return msstd_fs_file_chmod(self.native, mode)

    # Sets the owner and group of the open file by numeric id; -1 leaves that id unchanged. Usually needs privilege.
    fn chown(uid: Int, gid: Int) Unit!FileSystemError:
        return msstd_fs_file_chown(self.native, uid, gid)

    # Sets the access and modification times of the open file. Returns Unsupported on hosts without descriptor timestamps.
    fn set_times(accessed: Timestamp, modified: Timestamp) Unit!FileSystemError:
        return msstd_fs_file_set_times(self.native, accessed, modified)

    # Reads from the current position to the end and returns the lines with their `\n` or `\r\n` terminators removed.
    # Invalid UTF-8 returns InvalidData, and more bytes than `max_bytes` or lines than `max_lines` returns LimitExceeded. A negative `max_bytes` or `max_lines` returns InvalidInput.
    fn read_lines(max_bytes: Int?, max_lines: Int?) List[String]!FileSystemError:
        return msstd_fs_file_read_lines(self.native, max_bytes, max_lines)

# The runtime handle behind a `Directory`.
export extern type NativeDirectory

extern fn msstd_fs_directory_read(dir: NativeDirectory) DirectoryEntry?!FileSystemError

extern fn msstd_fs_directory_path(dir: NativeDirectory) String

extern fn msstd_fs_directory_close(dir: NativeDirectory) Unit

# An open directory that yields one child per read and must be closed.
export type Directory:
    # The runtime handle for the open directory; it is released by `close` and owned by this value.
    native: NativeDirectory

impl Closeable for Directory:
    # Releases the directory handle.
    # Safe to call repeatedly; later reads return Closed.
    var fn close() Unit!:
        msstd_fs_directory_close(self.native)
        return ok(unit)

impl Directory:
    # Returns the path this cursor was opened with.
    fn path() String:
        return msstd_fs_directory_path(self.native)

    # Returns the next child in native directory order, or none after the last one.
    # The order is not sorted.
    fn read() DirectoryEntry?!FileSystemError:
        return msstd_fs_directory_read(self.native)

# The runtime handle behind a `FileWatcher`.
export extern type NativeWatcher

extern fn msstd_fs_watch_next(watcher: NativeWatcher) List[FileEvent]!FileSystemError

extern fn msstd_fs_watch_close(watcher: NativeWatcher) Unit

# A change stream returned by a filesystem watch operation.
export type FileWatcher:
    # The runtime handle for the watch; it is released by `close` and owned by this value.
    native: NativeWatcher

impl Closeable for FileWatcher:
    # Stops the watcher, wakes a pending `next` with Closed, and waits for its worker to stop.
    # Safe to call repeatedly.
    var fn close() Unit!:
        msstd_fs_watch_close(self.native)
        return ok(unit)

impl FileWatcher:
    # Waits for filesystem activity and returns events. A native watcher returns one event per call; a polling watcher returns every difference seen after an interval.
    # Cancelling the waiting task unwinds it, and a closed watcher returns Closed. A native watcher that overflowed with policy `error` returns LimitExceeded.
    fn next() List[FileEvent]!FileSystemError:
        return msstd_fs_watch_next(self.native)

# The runtime handle behind a `TemporaryDirectory`.
export extern type NativeTemporary

extern fn msstd_fs_temporary_path(temporary: NativeTemporary) String

extern fn msstd_fs_temporary_close(temporary: NativeTemporary) Unit!FileSystemError

# A temporary directory whose contents are removed when it is closed.
export type TemporaryDirectory:
    # The runtime handle for the directory; it is released by `close` and owned by this value.
    native: NativeTemporary

impl Closeable for TemporaryDirectory:
    # Removes the directory and everything inside it.
    # Safe to call repeatedly.
    var fn close() Unit!:
        let _ = msstd_fs_temporary_close(self.native)
        return ok(unit)

impl TemporaryDirectory:
    # Returns the absolute path of the directory, created under the host's temporary root.
    fn path() String:
        return msstd_fs_temporary_path(self.native)

# One filesystem change and the affected path.
export type FileEvent:
    # Path of the affected entry, formed from the watched path plus any child components.
    path: String
    # Exactly `rename` (appearance/disappearance/rename) or `change` (contents/metadata).
    kind: String

# Capacity/free-space statistics: block_size is bytes, blocks/free/available are counts
# in those blocks, and files/files_free are native file-node counts (zero if unavailable).
export type FileSystemInfo:
    # The host's numeric filesystem type code, such as the magic number reported by Linux; 0 where unavailable.
    type_id: Int
    # Size in bytes of the blocks that `blocks`, `blocks_free`, and `blocks_available` count.
    block_size: Int
    # Total number of blocks in the filesystem.
    blocks: Int
    # Number of unused blocks, including space reserved for privileged users.
    blocks_free: Int
    # Number of unused blocks available to unprivileged users.
    blocks_available: Int
    # Total number of file nodes, such as inodes, the filesystem can hold; 0 where unavailable.
    files: Int
    # Number of unused file nodes; 0 where unavailable.
    files_free: Int

# Returns this host's filesystem flag, mode, and permission constants by name.
# Names and values vary by host; absent entries are not supported constants or portable enum cases.
export fn constants() Map[String, Int]:
    return msstd_fs_constants()

# Policies for recursive copies, including replacement, symlinks, and optional limits.
export type CopyOptions:
    # When True, directories are copied with their contents; when False, a directory source returns InvalidInput.
    recursive: Bool
    # When True, an existing destination file or link is replaced; when False, it is kept, or reported when `error_on_exists` is True.
    replace: Bool
    # When True and `replace` is False, an existing destination file returns AlreadyExists instead of being skipped silently.
    error_on_exists: Bool
    # When True, symbolic links are followed and their targets copied; when False, links are recreated as links.
    dereference: Bool
    # When True, copied files and directories keep the source's access and modification times.
    preserve_timestamps: Bool
    # When True, a copied link keeps its target text unchanged. When False, a relative target is rewritten relative to the source directory so it still reaches the original file.
    verbatim_symlinks: Bool
    # Exactly `none`, `try`, or `force`; other strings return InvalidInput.
    # try falls back to byte copying; force requires a native clone operation.
    clone: String
    # Most files, directories, and links visited, counting the root. Exceeding it returns LimitExceeded. none sets no limit.
    max_entries: Int?
    # Most file bytes copied in total. Exceeding it returns LimitExceeded. none sets no limit.
    max_bytes: Int?

# A matched path together with its filesystem entry metadata.
export type PathEntry:
    # The matched path relative to the glob root, using the host's separators.
    path: String
    # The directory entry record for the match: name, directory flag, and symlink flag.
    entry: DirectoryEntry

# Include and exclude patterns and limits used by filesystem glob operations.
export type GlobOptions:
    # Glob patterns to include; an entry that matches any of them is returned.
    patterns: List[String]
    # Glob patterns for entries to skip; a match is neither returned nor searched further.
    exclude: List[String]
    # When True, symbolic links to directories are traversed, with cycles detected; when False, links are reported but not entered.
    follow_links: Bool
    # Most filesystem entries visited while searching. Exceeding it returns LimitExceeded. none sets no limit.
    max_entries: Int?
    # Most distinct matches returned. Exceeding it returns LimitExceeded. none sets no limit.
    max_results: Int?

impl Error for FileSystemError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `filesystem: <reason>`, such as `filesystem: file or directory not found`.
    fn message() String:
        match self:
            InvalidInput: return "filesystem: invalid input"
            InvalidData: return "filesystem: invalid data"
            LimitExceeded: return "filesystem: limit exceeded"
            NotFound: return "filesystem: file or directory not found"
            AlreadyExists: return "filesystem: already exists"
            NotEmpty: return "filesystem: directory not empty"
            PermissionDenied: return "filesystem: permission denied"
            Unsupported: return "filesystem: operation not supported"
            Closed: return "filesystem: resource is closed"
            Failed(message): return message.clone()

# Returns filesystem operations for the current host.
export fn filesystem() FileSystem:
    return msstd_fs_filesystem()

# Errors returned when a path cannot be parsed or resolved.
export type PathError:
    # Invalid NUL input, a nonabsolute resolve/relative anchor or malformed glob syntax.
    case InvalidInput

# Returns the final path component, excluding trailing separators.
export fn basename(path: String) String:
    return msrt_path_basename(path)

# Returns the directory portion of a path.
export fn dirname(path: String) String:
    return msrt_path_dirname(path)

# Returns the final extension, including its leading dot, or an empty string.
export fn extension(path: String) String:
    return msrt_path_extension(path)

# Reports whether a path is absolute according to the host path rules.
export fn is_absolute(path: String) Bool:
    return msrt_path_is_absolute(path)

# Joins path parts using the host separator and normalizes the result.
export fn join(parts: List[String]) String:
    return msrt_path_join(parts)

# Normalizes separators and dot segments without accessing the filesystem.
export fn normalize(path: String) String:
    return msrt_path_normalize(path)

# Computes a relative path from `base` to `target` using host path rules.
export fn relative(base: String, target: String) String!PathError:
    return msrt_path_relative(base, target)

# Parsed path components using the familiar root, directory, base, extension, and name fields.
export type PathParts:
    # Root prefix under the chosen path rules, including a POSIX slash or Windows drive/UNC root.
    root: String
    # Directory portion, including the root when present; it takes precedence over root during format.
    directory: String
    # Final component with extension; it takes precedence over name/extension during format.
    base: String
    # Final extension including its dot; simple dotfiles and dot/dot-dot components have no extension.
    extension: String
    # Final component with its extension removed, retaining the original spelling.
    name: String

# Path operations using either POSIX or Windows path conventions.
export interface PathOperations:
    # Returns the last component after ignoring trailing separators under this view's path rules.
    fn basename(path: String) String
    # Removes an exact suffix under basename compatibility rules; it does not strip arbitrary extensions.
    fn basename_without(path: String, suffix: String) String
    # Returns the directory component using the selected POSIX or Windows convention.
    fn dirname(path: String) String
    # Returns the final dot extension, or empty text for extensionless names and simple dotfiles.
    fn extension(path: String) String
    # Tests absolute-root syntax; a Windows drive-relative spelling is not absolute.
    fn is_absolute(path: String) Bool
    # Joins nonempty parts and normalizes separators/dot segments without filesystem access.
    fn join(parts: List[String]) String
    # Cleans repeated separators and dot segments lexically; it does not resolve symlinks.
    fn normalize(path: String) String
    # Computes a lexical relative path from absolute anchors; different roots return the original target.
    # Nonabsolute anchors or invalid NUL input return InvalidInput.
    fn relative(base: String, target: String) String!PathError
    # Resolves parts against an explicit absolute base; no process working directory is consulted.
    fn resolve(base: String, parts: List[String]) String!PathError
    # Splits the original spelling into root, directory, base, extension and name without filesystem access.
    fn parse(path: String) PathParts
    # Builds a path with directory preferred over root, and base preferred over name plus extension.
    fn format(parts: PathParts) String
    # Returns slash for POSIX or backslash for Windows path components.
    fn separator() String
    # Returns colon for POSIX or semicolon for Windows path-list entries.
    fn delimiter() String
    # Returns a Windows namespaced absolute path when applicable; POSIX paths are unchanged.
    fn to_namespaced_path(path: String) String
    # Tests one lexical path against the supported glob syntax; malformed patterns return InvalidInput.
    fn matches_glob(path: String, pattern: String) Bool!PathError

# Returns path operations using POSIX separators and parsing rules.
export fn posix() PathOperations:
    return msstd_fs_posix()

# Returns path operations using Windows separators and parsing rules.
export fn win32() PathOperations:
    return msstd_fs_win32()

# Returns the basename with the supplied suffix removed when it matches.
export fn basename_without(path: String, suffix: String) String:
    return msrt_path_basename_without(path, suffix)

# Resolves path parts against a base using host path conventions.
export fn resolve(base: String, parts: List[String]) String!PathError:
    return msrt_path_resolve(base, parts)

# Splits a path into its root, directory, base, extension, and name.
export fn parse(path: String) PathParts:
    return msrt_path_parse(path)

# Formats parsed path components as a path string.
export fn format(parts: PathParts) String:
    return msrt_path_format(parts)

# Returns the host's path separator.
export fn separator() String:
    return msrt_path_separator()

# Returns the host's path-list delimiter.
export fn delimiter() String:
    return msrt_path_delimiter()

# Converts a path to the host's namespaced representation when applicable.
export fn to_namespaced_path(path: String) String:
    return msrt_path_to_namespaced_path(path)

# Tests a path against a glob pattern.
export fn matches_glob(path: String, pattern: String) Bool!PathError:
    return msrt_path_matches_glob(path, pattern)

impl Error for PathError:
    # Returns a path-prefixed diagnostic without revealing the supplied paths or pattern.
    fn message() String:
        match self:
            InvalidInput: return "path: invalid input"
