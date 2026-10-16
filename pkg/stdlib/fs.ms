# Canonical standard-library declarations. Implementations are native.

import BigInt from "@std/bigint.ms"
import Bytes from "@std/bytes.ms"
import ReadStream from "@std/io.ms"
import WriteStream from "@std/io.ms"
import Duration from "@std/time.ms"
import Timestamp from "@std/time.ms"

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
    # The destination exists and the operation refuses to replace it, such as exclusive creation with `replace: false`.
    case AlreadyExists
    # Removal failed because the directory still contains entries.
    case NotEmpty
    # The operating system refused access to the path or operation.
    case PermissionDenied
    # The host or filesystem cannot perform the operation, or a file name is not valid UTF-8.
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
    created: Optional[Timestamp]
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
    fn open_flags(
        path: String,
        flags: Int,
        mode: Int
    ) -> Result[FileHandle, FileSystemError]
    # Returns entries matching the supplied include and exclude patterns.
    fn glob_entries(
        path: String,
        options: GlobOptions,
        exclude: Optional[fn(entry: PathEntry) -> Bool]
    ) -> Result[List[PathEntry], FileSystemError]
    # Copies a file or tree according to the supplied replacement and size policies.
    fn copy(
        source: String,
        destination: String,
        options: CopyOptions,
        filter: Optional[fn(source: String, destination: String) -> Bool]
    ) -> Result[Unit, FileSystemError]
    # Watches native OS events; overflow is exactly `error` or `ignore` (case-sensitive).
    # Other policies return InvalidInput. Limits bound tracked paths and queued events.
    fn watch_native(
        path: String,
        recursive: Bool,
        max_entries: Optional[Int] = none,
        max_events: Optional[Int] = none,
        overflow: String
    ) -> Result[FileWatcher, FileSystemError]
    # Resolves symlinks and returns the canonical absolute path.
    fn canonicalize(path: String) -> Result[String, FileSystemError]
    # Copies one file; replace defaults to false, refusing an existing destination.
    fn copy_file(
        source: String,
        destination: String,
        replace: Bool = false,
        max_bytes: Optional[Int] = none
    ) -> Result[Unit, FileSystemError]
    # Creates one directory; recursive defaults to false, requiring its parent to exist.
    fn create_directory(
        path: String,
        recursive: Bool = false
    ) -> Result[Unit, FileSystemError]
    # Creates a symbolic link at `path` pointing to `target`.
    fn create_link(path: String, target: String) -> Result[Unit, FileSystemError]
    # Lists a directory, optionally limiting the number of returned entries.
    fn list(
        path: String,
        max_entries: Optional[Int] = none
    ) -> Result[List[DirectoryEntry], FileSystemError]
    # Reads a file fully into memory. Supply `max_bytes` for untrusted or large files.
    fn read_file(
        path: String,
        max_bytes: Optional[Int] = none
    ) -> Result[Bytes, FileSystemError]
    # Returns the target text stored in the symbolic link at `path`, without resolving it.
    # A path that is not a link returns InvalidInput.
    fn read_link(path: String) -> Result[String, FileSystemError]
    # Removes a file or empty directory; recursive defaults to false, retaining nonempty trees.
    fn remove(path: String, recursive: Bool = false) -> Result[Unit, FileSystemError]
    # Moves `source` to `destination` using the operating system's rename, applying its rules for replacing an existing destination.
    # It never falls back to copying, so a move across devices returns an error.
    fn rename(source: String, destination: String) -> Result[Unit, FileSystemError]
    # Returns metadata for `path`. `follow_links` true describes the link target and false describes the link itself.
    fn stat(path: String, follow_links: Bool) -> Result[FileInfo, FileSystemError]
    # Creates a new directory under the host temp root; the caller must remove it.
    # Prefix must be nonempty and contain no slash, backslash, or NUL.
    fn temporary_directory(prefix: String) -> Result[String, FileSystemError]
    # Creates a file exclusively; replace defaults to false, retaining an existing file.
    fn write_file(
        path: String,
        data: Bytes,
        replace: Bool = false
    ) -> Result[Unit, FileSystemError]
    # Checks access with mode 0..7: existence 0, read 4, write 2, execute 1, or combined bits.
    # Native permissions and Windows access policy still apply.
    fn access(path: String, mode: Int) -> Result[Unit, FileSystemError]
    # Appends `data` to the end of the file, creating it with mode 0600 when absent. Writes every byte or fails, possibly leaving a partial append.
    fn append_file(path: String, data: Bytes) -> Result[Unit, FileSystemError]
    # Changes target permissions with mode 0..4095; follows a final symbolic link.
    fn chmod(path: String, mode: Int) -> Result[Unit, FileSystemError]
    # Sets the owning user and group of `path` by numeric id; -1 leaves that id unchanged.
    # `follow_links` chooses the link target (true) or the link itself (false). Usually needs privilege, and Windows returns Unsupported.
    fn chown(
        path: String,
        uid: Int,
        gid: Int,
        follow_links: Bool
    ) -> Result[Unit, FileSystemError]
    # Sets the target size in bytes; follows a final symbolic link.
    fn truncate(path: String, size: Int) -> Result[Unit, FileSystemError]
    # Sets the access and modification times of `path`.
    # `follow_links` chooses the link target (true) or the link itself (false); no-follow updates return Unsupported where the host lacks them, such as Windows.
    fn set_times(
        path: String,
        accessed: Timestamp,
        modified: Timestamp,
        follow_links: Bool
    ) -> Result[Unit, FileSystemError]
    # Creates `destination` as another name for the file at `source`.
    # An existing destination returns AlreadyExists; it must be on the same filesystem as `source`.
    fn hard_link(source: String, destination: String) -> Result[Unit, FileSystemError]
    # Opens with exactly r, r+, w, wx, w+, wx+, a, ax, a+, or ax+; other strings return InvalidInput.
    # Mode is permission bits in 0..4095, applied on creation subject to umask/OS policy.
    fn open(
        path: String,
        flags: String,
        mode: Int
    ) -> Result[FileHandle, FileSystemError]
    # Opens `path` as a directory cursor that yields one child per `read` in native order; close it when done.
    # A path that is not a directory returns InvalidInput.
    fn open_directory(path: String) -> Result[Directory, FileSystemError]
    # Copies a tree; replace defaults to false, refusing existing destinations.
    # Entry and byte limits remain separate and apply cumulatively across the copy.
    fn copy_tree(
        source: String,
        destination: String,
        replace: Bool = false,
        max_entries: Optional[Int] = none,
        max_bytes: Optional[Int] = none
    ) -> Result[Unit, FileSystemError]
    # Returns the sorted relative paths under `path` matching `pattern`, without following directory symlinks.
    # A malformed pattern, or one over 4096 bytes, or a negative `max_entries` returns InvalidInput. Matches beyond `max_entries` return LimitExceeded.
    fn glob(
        path: String,
        pattern: String,
        max_entries: Optional[Int] = none
    ) -> Result[List[String], FileSystemError]
    # Returns a polling watcher that compares snapshots of `path` every `interval`, which must be positive.
    # `max_entries` bounds the tracked paths; exceeding it returns LimitExceeded. Transient changes between polls can be missed.
    fn watch(
        path: String,
        recursive: Bool,
        interval: Duration,
        max_entries: Optional[Int] = none
    ) -> Result[FileWatcher, FileSystemError]
    # Creates a new temp directory whose contents are removed by scoped close.
    # Prefix has the same validation as temporary_directory; this does not query the temp root.
    fn temporary(prefix: String) -> Result[TemporaryDirectory, FileSystemError]
    # Returns capacity and free-space statistics for the filesystem containing `path`.
    # Hosts without the query return Unsupported.
    fn stat_filesystem(path: String) -> Result[FileSystemInfo, FileSystemError]
    # Changes the link itself without following it; Unsupported on hosts lacking this operation.
    fn chmod_link(path: String, mode: Int) -> Result[Unit, FileSystemError]

# An open file supporting sequential and positional I/O.
export interface FileHandle:
    # Adapts this handle to IoError/Optional chunk reads; closing either view closes all aliases.
    fn reader() -> ReadStream
    # Adapts complete writes to IoError/Unit; flush synchronizes the file.
    fn writer() -> WriteStream
    # Closes the file, interrupts calls in progress, and waits for them to stop.
    # Safe to call repeatedly; later operations return Closed.
    fn close() -> Unit
    # Returns a positive chunk (at most 64 KiB), or none at EOF; a supplied size must be positive.
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], FileSystemError]
    # Writes all bytes at the current position; errors can leave a prefix. Does not truncate or reposition this handle.
    fn write(data: Bytes) -> Result[Unit, FileSystemError]
    # Writes at the current position; appends only when the handle was opened in append mode.
    fn append_file(data: Bytes) -> Result[Unit, FileSystemError]
    # Reads at a nonnegative byte offset without moving the position; short/empty Bytes mark EOF.
    fn read_at(
        offset: Int,
        max_bytes: Optional[Int] = none
    ) -> Result[Bytes, FileSystemError]
    # Writes all bytes at a nonnegative offset without moving the position; errors can leave a prefix.
    fn write_at(offset: Int, data: Bytes) -> Result[Unit, FileSystemError]
    # Reads remaining bytes from the current position; EOF returns empty Bytes.
    fn read_file(max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
    # Reads consecutive buffers of the given `sizes` in bytes, each up to 65536 and all together up to 16 MiB, and returns the bytes obtained for each.
    # `offset` -1 reads from the current position; other offsets read without moving it. A buffer is shorter than requested at end of file. A negative size or offset below -1 returns InvalidInput.
    fn read_vectors(
        sizes: List[Int],
        offset: Int
    ) -> Result[List[Bytes], FileSystemError]
    # Writes every buffer; offset -1 uses the current position.
    fn write_vectors(buffers: List[Bytes], offset: Int) -> Result[Unit, FileSystemError]
    # Seeks in bytes with origin exactly 0 (start), 1 (current), or 2 (end).
    # Other origins return InvalidInput; the OS validates the resulting offset.
    fn seek(offset: Int, origin: Int) -> Result[Int, FileSystemError]
    # Returns metadata for the open file.
    fn stat() -> Result[FileInfo, FileSystemError]
    # Sets the file length to `size` bytes, discarding the excess or extending with zero bytes. The current position is not moved.
    # A negative size returns InvalidInput.
    fn truncate(size: Int) -> Result[Unit, FileSystemError]
    # Flushes the file's data and metadata to stable storage.
    fn sync() -> Result[Unit, FileSystemError]
    # Flushes the file's data to stable storage, skipping metadata that is not needed to read it back where the host allows.
    # Hosts without a separate data sync perform a full sync.
    fn data_sync() -> Result[Unit, FileSystemError]
    # Sets the permission bits of the open file to `mode` (0 through 4095).
    fn chmod(mode: Int) -> Result[Unit, FileSystemError]
    # Sets the owner and group of the open file by numeric id; -1 leaves that id unchanged. Usually needs privilege.
    fn chown(uid: Int, gid: Int) -> Result[Unit, FileSystemError]
    # Sets the access and modification times of the open file. Returns Unsupported on hosts without descriptor timestamps.
    fn set_times(
        accessed: Timestamp,
        modified: Timestamp
    ) -> Result[Unit, FileSystemError]
    # Reads from the current position to the end and returns the lines with their `\n` or `\r\n` terminators removed.
    # Invalid UTF-8 returns InvalidData, and more bytes than `max_bytes` or lines than `max_lines` returns LimitExceeded.
    fn read_lines(
        max_bytes: Optional[Int] = none,
        max_lines: Optional[Int] = none
    ) -> Result[List[String], FileSystemError]

# An open directory that yields one child per read and must be closed.
export interface Directory:
    # Returns the path this cursor was opened with.
    fn path() -> String
    # Releases the directory handle.
    # Safe to call repeatedly; later reads return Closed.
    fn close() -> Unit
    # Returns the next child in native directory order, or none after the last one.
    # The order is not sorted.
    fn read() -> Result[Optional[DirectoryEntry], FileSystemError]

# A change stream returned by a filesystem watch operation.
export interface FileWatcher:
    # Stops the watcher, wakes a pending `next` with Closed, and waits for its worker to stop.
    # Safe to call repeatedly.
    fn close() -> Unit
    # Waits for filesystem activity and returns events. A native watcher returns one event per call; a polling watcher returns every difference seen after an interval.
    # Cancelling the waiting task unwinds it, and a closed watcher returns Closed. A native watcher that overflowed with policy `error` returns LimitExceeded.
    fn next() -> Result[List[FileEvent], FileSystemError]

# A temporary directory whose contents are removed when it is closed.
export interface TemporaryDirectory:
    # Removes the directory and everything inside it.
    # Safe to call repeatedly.
    fn close() -> Unit
    # Returns the absolute path of the directory, created under the host's temporary root.
    fn path() -> String

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
export fn constants() -> Map[String, Int]:

# Policies for recursive copies, including replacement, symlinks, and optional limits.
export type CopyOptions:
    # When true, directories are copied with their contents; when false, a directory source returns InvalidInput.
    recursive: Bool
    # When true, an existing destination file or link is replaced; when false, it is kept, or reported when `error_on_exists` is true.
    replace: Bool
    # When true and `replace` is false, an existing destination file returns AlreadyExists instead of being skipped silently.
    error_on_exists: Bool
    # When true, symbolic links are followed and their targets copied; when false, links are recreated as links.
    dereference: Bool
    # When true, copied files and directories keep the source's access and modification times.
    preserve_timestamps: Bool
    # When true, a copied link keeps its target text unchanged. When false, a relative target is rewritten relative to the source directory so it still reaches the original file.
    verbatim_symlinks: Bool
    # Exactly `none`, `try`, or `force`; other strings return InvalidInput.
    # try falls back to byte copying; force requires a native clone operation.
    clone: String
    # Most files, directories, and links visited, counting the root. Exceeding it returns LimitExceeded. none sets no limit.
    max_entries: Optional[Int] = none
    # Most file bytes copied in total. Exceeding it returns LimitExceeded. none sets no limit.
    max_bytes: Optional[Int] = none

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
    # When true, symbolic links to directories are traversed, with cycles detected; when false, links are reported but not entered.
    follow_links: Bool
    # Most filesystem entries visited while searching. Exceeding it returns LimitExceeded. none sets no limit.
    max_entries: Optional[Int] = none
    # Most distinct matches returned. Exceeding it returns LimitExceeded. none sets no limit.
    max_results: Optional[Int] = none

impl Error for FileSystemError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `filesystem: <reason>`, such as `filesystem: file or directory not found`.
    fn message() -> String:

# Returns filesystem operations for the current host.
export fn filesystem() -> FileSystem:

# documentation documentation/standard-library/filesystem.md
# +++
# title = "Files and paths"
# weight = 10
# +++
#
# # Files and paths
#
# Path functions manipulate path text without accessing disk. FileSystem methods read or change files through a supplied service. A path string or an import alone does not grant filesystem access.
#
# See the [filesystem reference](reference/fs.md) and [path reference](reference/path.md) for types, methods, and import paths.
#
# ## Files and directories
#
# Import `filesystem()` from `@std/fs.ms` to obtain the filesystem service. Acquire handles inside `with`. This fragment belongs in a function returning `Result[Unit, FileSystemError]`:
#
# ```manuscript
# with file = try filesystem().open(path: path, flags: "r+", mode: 384):
#     try file.write_at(offset: 0, data: "HELLO".to_bytes())
#     let bytes = try file.read_at(offset: 0, max_bytes: 5)
#     let synced = try file.sync()
# ```
#
# `384` is decimal for Unix permission bits `0600`. Opening accepts `r`, `r+`, `w`, `wx`, `w+`, `wx+`, `a`, `ax`, `a+`, and `ax+`. `x` makes creation exclusive. Permission arguments accept `0..4095` (`07777`), including setuid, setgid, and sticky bits where the native OS supports them. `open_flags` accepts numeric native flags from `fs.constants()`; these numbers and available names are host-specific. The validator accepts flags in `0..2147483647`; it does not reject every unknown bit or invalid combination before calling the OS. This is an OS bitmask boundary, not a closed portable enum. Paths use the native filesystem dialect, reject empty strings and NUL with `FileSystemError.InvalidInput`, and use host OS permissions. Relative paths on CLI roots use the live working directory (`ms test` sets it to the project directory, or the test file's directory, so fixtures are found regardless of the caller's directory); embedded capabilities constructed with a directory retain that base. Importing the FileSystem type alone does not obtain a service.
#
# ## File reads and writes
#
# `read_file` limits cumulative bytes and closes its handle on every exit. `write_file`, `copy_file`, and `copy_tree` default to `replace: false`, refusing existing destinations. `write_file` creates exclusively; explicit `replace: true` may truncate existing data. Default creation permissions are 0600 for files and 0700 for directories, subject to platform behavior. Writes and copies can leave a partial destination after an error.
#
# `FileHandle` supports sequential `read`/`write`, positional `read_at`/`write_at`, bounded `read_file`, `append_file`, `read_vectors`/`write_vectors`, `read_lines`, `seek`, `stat`, `truncate`, `chmod`, `chown`, `set_times`, `sync`, `data_sync`, and idempotent `close`. Offsets, sizes, and returned counts are bytes. Omitted chunk reads request 64 KiB; supplied chunk sizes must be positive and are clamped to 64 KiB. A chunk may be shorter than requested; sequential EOF is `none`, positional EOF is empty `Bytes`. `read_vectors` accepts each size up to 64 KiB and a combined size up to 16 MiB. Vector offset `-1` uses the current position. Seek origins are `0` (start), `1` (current), and `2` (end). `read_file` and `read_lines` start at the current position. Line reads validate UTF-8, remove line terminators, and enforce both byte and line limits.
#
# Native `write`, `write_at`, `write_vectors`, and `append_file` loop until every input byte is written and return `Unit`, matching `WriteStream.write` and `Connection.write`. On failure, the Result contains only the error; a count of the external prefix is not returned. Neither repositions or truncates an existing handle; handle `append_file` appends only if its open mode includes append. Positional I/O leaves the shared sequential position unchanged.
#
# ## Streams and close
#
# `reader()` and `writer()` adapt the same handle to the existing stream contracts, translating `FileSystemError` into `IoError`: `Closed` and `InvalidInput` retain their cases, while all other cases become `IoError.Failed`. An existing `Failed(message)` retains its text; other cases use the filesystem case name as the payload. The adapter does not preserve a filesystem error as a structured cause. Closing an adapter closes the handle and every alias. `flush` synchronizes the file; this is stronger than flushing a userspace buffer. Operations serialize shared file positions. Close prevents new calls, interrupts pollable I/O, and joins admitted calls. Parent cancellation unwinds; it is not EOF. Acquisition releases a resource when cancellation wins before delivery. Regular-file OS calls can delay cancellation until they return.
#
# ## Directories and metadata
#
# `create_directory` and `remove` default to `recursive: false`. Creation requires an existing parent; removal accepts a file or empty directory and refuses a nonempty directory. Pass `recursive: true` to create missing parents or remove a tree. Link-following choices remain explicit.
#
# Host errors map to typed cases: `NotFound`, `AlreadyExists`, `PermissionDenied`, `NotEmpty` (removing a non-empty directory without `recursive`), and `InvalidInput` for caller mistakes such as listing or reading the wrong kind of entry, a negative seek offset, or using a handle opened without the needed read or write mode. `Failed` keeps host text only for unexpected errors. Directory lists are sorted. Excess entries return `LimitExceeded`, rather than a truncated success. `stat` uses `follow_links` to select link or target metadata. `rename` uses native replacement and atomicity rules and does not fall back to copying across devices. Removal rejects final `.` or `..` components, filesystem roots, the filesystem base (the live working directory for CLI services), and its ancestors with `FileSystemError.InvalidInput` before deleting any entries. Directory aliases through intermediate symlinks are checked by identity. An explicit descendant can still be removed; a final symlink is removed as a link, including with a trailing separator. Recursive removal does not intentionally follow symlinks and checks cancellation between entries. These checks prevent accidental base removal; they are not a filesystem sandbox or a guarantee against concurrent external path replacement.
#
# `System.temporary_directory()` queries the host temp root without creating anything or checking that it exists. Both filesystem factories create a new directory under that root, independently of the filesystem service's base. Temporary-directory prefixes must be nonempty and contain no slash, backslash, or NUL. `temporary_directory` returns a path that the caller must remove; `temporary` returns a scoped resource that removes its directory on close.
#
# `list` returns sorted `DirectoryEntry` records in one allocated list; `glob` returns sorted relative path strings; `glob_entries` returns deduplicated path/entry records with separate traversal/result budgets. `open_directory().read()` is an incremental cursor in native directory order, ending in `none`. These are different result views and access patterns, rather than interchangeable name lists.
#
# `create_link(path, target)` creates a symbolic link; `hard_link(source, destination)` creates another name for the same file. `read_link` reads the stored target. `chmod`, `truncate`, and `access` follow a final symbolic link; use `chmod_link` to change a link itself when supported. `stat`, `chown`, and `set_times` select link versus target explicitly with `follow_links`.
#
# Directory cursors expose their native `path()` and return one `DirectoryEntry` or `none` and require close. `FileInfo.mode` contains POSIX type and permission bits; `permissions` contains only permission/special bits. The record supplies byte size, modified/accessed/changed times, optional `created` birth time, preferred I/O block size in bytes and allocated 512-byte blocks on POSIX, device/inode/link count, owner IDs, and regular/symlink/directory/FIFO/socket/device classifications. FileSystemInfo.block_size is bytes; blocks/free/available are counts in that block size, and files/files_free are native file-node counts. `exact` contains arbitrary-precision numeric metadata and nanosecond timestamps. Native fields absent on a host are zero; unavailable birth time is `none`. Accessed/changed times fall back to modified time when unavailable, including the current Windows adapter. Linux does not support no-follow chmod; macOS supports no-follow chmod and timestamps. Windows supports descriptor timestamps, while no-follow metadata updates return `Unsupported`. Windows permission bits express native read/write policy.
#
# ## Numeric access and permissions
#
# `access` accepts `0..7`: existence is `0`, and read/write/execute bits are `4`, `2`, and `1`. Combined values are accepted. On Windows the adapter checks existence and read/write access; the execute bit is not a POSIX executable-permission check. `chmod`, `chmod_link`, and creation modes accept permission/special bits in `0..4095`, subject to OS policy and process umask. These are bit values, not alternate open modes. Seek origins alone form a closed numeric set: `0` start, `1` current, and `2` end.
#
# ## Copying trees
#
# `copy` accepts `CopyOptions`: recursive traversal, replacement, error-on-existing, dereferencing, timestamp preservation, verbatim symlinks, case-sensitive clone policy (`none`, `try`, or `force`; other strings return `InvalidInput`), and shared entry/byte budgets. An optional filter runs sequentially for each source/destination pair and can prune directories. Without dereferencing, links are copied as links; relative targets are resolved against the source unless verbatim copying is requested. Dereferencing detects ancestor cycles. Copy rejects copying a tree into itself and traversing a destination symlink as a directory. Existing directories merge; collisions skip, fail, or replace according to the options. Native cloning uses Linux reflinks or macOS clonefile; `try` falls back to byte copying and `force` reports an OS error when unavailable. Windows has no clone adapter. The root and descendants share `max_entries`; all copied data shares `max_bytes`. Copying and writing can leave a partial prefix after an error.
#
# ## Watching files
#
# `watch_native` retains OS events while the caller is busy. It bounds directory watches with `max_entries` and buffered events with `max_events`; case-sensitive overflow policy `error` returns `LimitExceeded`, while `ignore` drops excess events. Other overflow strings return `InvalidInput`. Recursive watches admit newly created directories and do not follow directory symlinks. Events use `rename` for creation/removal/rename and `change` for writes/metadata changes. OS backends can coalesce events, report a containing directory, or overflow; event names and granularity are platform-dependent. Close stops the backend and joins its worker and admitted waiter. Cancellation during acquisition releases the backend.
#
# Polling `watch` compares bounded snapshots after each requested interval. They report sorted `FileEvent` records with `rename` for appearance/disappearance and `change` for changed metadata. A vanished root reports disappearance. Recursive watches do not follow symlinks. Polling can coalesce or miss transient changes between snapshots; this is not a native OS event stream. Close and parent cancellation interrupt a waiting `next` without leaving a worker running.
#
# ## Path functions
#
# Import pure path functions from `@std/path.ms`, or use `posix()`/`win32()` for a dialect independent of the host. Module functions select the host dialect; the explicit views expose the same operation family for parsing foreign path text without changing the host filesystem dialect. No path operation reads cwd or touches files. `join` and `normalize` only clean path text; this does not prove that a path stays inside an authorized directory. `relative` requires absolute paths; paths on different Windows roots produce the absolute target. A leading dot alone does not form an extension: `extension(".profile")` returns an empty string, while `extension("notes.txt")` returns `".txt"`.
#
# Windows parsing preserves the spelling of separators. Normalization emits backslashes. UNC and drive roots remain distinct; relative comparisons are case-insensitive for Windows. Drive-relative components use an earlier explicit absolute base on the chosen drive; an unknown drive base returns `InvalidInput`, since resolving it would require ambient per-drive cwd. Later absolute components supersede earlier paths. Relative identical paths produce an empty string. `PathParts.directory` and `base` take precedence over `root`, `name`, and `extension` when formatting.
#
# ## Glob patterns
#
# Globs support segment wildcards, character classes, `**`, brace alternatives, numeric brace ranges, and `@`, `+`, `?`, `*`, `!` extended groups. Hidden segments require an explicit leading dot. Patterns are limited to 4096 bytes; numeric ranges have at most 1025 entries and endpoints within `-100000..100000`. Use `/` between filesystem glob segments on every host. Brace alternatives can cross directory separators; alphabetic and padded numeric ranges are supported. Basic filesystem `glob` returns sorted relative paths without following directory symlinks; its `max_entries` bounds matched output. `glob_entries` accepts multiple patterns, pattern/callback exclusions that prune traversal, optional link following with cycle prevention, and separate visited-entry/result limits. Results are sorted, deduplicated `PathEntry` records. Absolute and parent-relative patterns can visit outside the supplied base, within the authority granted by the filesystem capability.
# end-documentation
