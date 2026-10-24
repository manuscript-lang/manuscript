from "@std/math.ms" import BigInt
from "@std/bytes.ms" import Bytes
from "@std/time.ms" import Duration
from "@std/io.ms" import ReadStream
from "@std/time.ms" import Timestamp
from "@std/io.ms" import WriteStream

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
    def open_flags(
        path: String,
        flags: Int,
        mode: Int
    ) -> Result[FileHandle, FileSystemError]
    # Returns entries matching the supplied include and exclude patterns.
    def glob_entries(
        path: String,
        options: GlobOptions,
        exclude: Optional[Callable[[PathEntry], Bool]]
    ) -> Result[List[PathEntry], FileSystemError]
    # Copies a file or tree according to the supplied replacement and size policies.
    def copy(
        source: String,
        destination: String,
        options: CopyOptions,
        filter: Optional[Callable[[String, String], Bool]]
    ) -> Result[Unit, FileSystemError]
    # Watches native OS events; overflow is exactly `error` or `ignore` (case-sensitive).
    # Other policies return InvalidInput. Limits bound tracked paths and queued events.
    def watch_native(
        path: String,
        recursive: Bool,
        max_entries: Optional[Int] = none,
        max_events: Optional[Int] = none,
        overflow: String
    ) -> Result[FileWatcher, FileSystemError]
    # Resolves symlinks and returns the canonical absolute path.
    def canonicalize(path: String) -> Result[String, FileSystemError]
    # Copies one file; replace defaults to false, refusing an existing destination.
    def copy_file(
        source: String,
        destination: String,
        replace: Bool = False,
        max_bytes: Optional[Int] = none
    ) -> Result[Unit, FileSystemError]
    # Creates one directory; recursive defaults to false, requiring its parent to exist.
    def create_directory(
        path: String,
        recursive: Bool = False
    ) -> Result[Unit, FileSystemError]
    # Creates a symbolic link at `path` pointing to `target`.
    def create_link(path: String, target: String) -> Result[Unit, FileSystemError]
    # Lists a directory, optionally limiting the number of returned entries.
    def list(
        path: String,
        max_entries: Optional[Int] = none
    ) -> Result[List[DirectoryEntry], FileSystemError]
    # Reads a file fully into memory. Supply `max_bytes` for untrusted or large files.
    def read_file(
        path: String,
        max_bytes: Optional[Int] = none
    ) -> Result[Bytes, FileSystemError]
    # Returns the target text stored in the symbolic link at `path`, without resolving it.
    # A path that is not a link returns InvalidInput.
    def read_link(path: String) -> Result[String, FileSystemError]
    # Removes a file or empty directory; recursive defaults to false, retaining nonempty trees.
    def remove(path: String, recursive: Bool = False) -> Result[Unit, FileSystemError]
    # Moves `source` to `destination` using the operating system's rename, applying its rules for replacing an existing destination.
    # It never falls back to copying, so a move across devices returns an error.
    def rename(source: String, destination: String) -> Result[Unit, FileSystemError]
    # Returns metadata for `path`. `follow_links` true describes the link target and false describes the link itself.
    def stat(path: String, follow_links: Bool) -> Result[FileInfo, FileSystemError]
    # Queries the host temp root without creating or checking a directory.
    def temporary_root() -> Result[String, FileSystemError]
    # Creates a new directory under the host temp root; the caller must remove it.
    # Prefix must be nonempty and contain no slash, backslash, or NUL.
    def temporary_directory(prefix: String) -> Result[String, FileSystemError]
    # Creates a file exclusively; replace defaults to false, retaining an existing file.
    def write_file(
        path: String,
        data: String,
        replace: Bool = False
    ) -> Result[Unit, FileSystemError]
    # Creates a file exclusively from raw bytes; replace defaults to false, retaining an existing file.
    def write_file_bytes(
        path: String,
        data: Bytes,
        replace: Bool = False
    ) -> Result[Unit, FileSystemError]
    # Checks access with mode 0..7: existence 0, read 4, write 2, execute 1, or combined bits.
    # Native permissions and Windows access policy still apply.
    def access(path: String, mode: Int) -> Result[Unit, FileSystemError]
    # Appends `data` to the end of the file, creating it with mode 0600 when absent. Writes every byte or fails, possibly leaving a partial append.
    def append_file(path: String, data: String) -> Result[Unit, FileSystemError]
    # Appends raw bytes to the end of the file, with the same creation and partial-write rules as append_file.
    def append_file_bytes(path: String, data: Bytes) -> Result[Unit, FileSystemError]
    # Changes target permissions with mode 0..4095; follows a final symbolic link.
    def chmod(path: String, mode: Int) -> Result[Unit, FileSystemError]
    # Sets the owning user and group of `path` by numeric id; -1 leaves that id unchanged.
    # `follow_links` chooses the link target (true) or the link itself (false). Usually needs privilege, and Windows returns Unsupported.
    def chown(
        path: String,
        uid: Int,
        gid: Int,
        follow_links: Bool
    ) -> Result[Unit, FileSystemError]
    # Sets the target size in bytes; follows a final symbolic link.
    def truncate(path: String, size: Int) -> Result[Unit, FileSystemError]
    # Sets the access and modification times of `path`.
    # `follow_links` chooses the link target (true) or the link itself (false); no-follow updates return Unsupported where the host lacks them, such as Windows.
    def set_times(
        path: String,
        accessed: Timestamp,
        modified: Timestamp,
        follow_links: Bool
    ) -> Result[Unit, FileSystemError]
    # Creates `destination` as another name for the file at `source`.
    # An existing destination returns AlreadyExists; it must be on the same filesystem as `source`.
    def hard_link(source: String, destination: String) -> Result[Unit, FileSystemError]
    # Opens with exactly r, r+, w, wx, w+, wx+, a, ax, a+, or ax+; other strings return InvalidInput.
    # Mode is permission bits in 0..4095, applied on creation subject to umask/OS policy.
    def open(
        path: String,
        flags: String,
        mode: Int
    ) -> Result[FileHandle, FileSystemError]
    # Opens `path` as a directory cursor that yields one child per `read` in native order; close it when done.
    # A path that is not a directory returns InvalidInput.
    def open_directory(path: String) -> Result[Directory, FileSystemError]
    # Copies a tree; replace defaults to false, refusing existing destinations.
    # Entry and byte limits remain separate and apply cumulatively across the copy.
    def copy_tree(
        source: String,
        destination: String,
        replace: Bool = False,
        max_entries: Optional[Int] = none,
        max_bytes: Optional[Int] = none
    ) -> Result[Unit, FileSystemError]
    # Returns the sorted relative paths under `path` matching `pattern`, without following directory symlinks.
    # A malformed pattern, or one over 4096 bytes, or a negative `max_entries` returns InvalidInput. Matches beyond `max_entries` return LimitExceeded.
    def glob(
        path: String,
        pattern: String,
        max_entries: Optional[Int] = none
    ) -> Result[List[String], FileSystemError]
    # Returns a polling watcher that compares snapshots of `path` every `interval`, which must be positive.
    # `max_entries` bounds the tracked paths; exceeding it returns LimitExceeded. Transient changes between polls can be missed.
    def watch(
        path: String,
        recursive: Bool,
        interval: Duration,
        max_entries: Optional[Int] = none
    ) -> Result[FileWatcher, FileSystemError]
    # Creates a new temp directory whose contents are removed by scoped close.
    # Prefix has the same validation as temporary_directory; this does not query the temp root.
    def temporary(prefix: String) -> Result[TemporaryDirectory, FileSystemError]
    # Returns capacity and free-space statistics for the filesystem containing `path`.
    # Hosts without the query return Unsupported.
    def stat_filesystem(path: String) -> Result[FileSystemInfo, FileSystemError]
    # Changes the link itself without following it; Unsupported on hosts lacking this operation.
    def chmod_link(path: String, mode: Int) -> Result[Unit, FileSystemError]

# An open file supporting sequential and positional I/O.
export interface FileHandle:
    # Adapts this handle to IoError/Optional chunk reads; closing either view closes all aliases.
    def reader() -> ReadStream
    # Adapts complete writes to IoError/Unit; flush synchronizes the file.
    def writer() -> WriteStream
    # Closes the file, interrupts calls in progress, and waits for them to stop.
    # Safe to call repeatedly; later operations return Closed.
    def close() -> Unit
    # Returns a positive chunk (at most 64 KiB), or none at EOF; a supplied size must be positive.
    def read(
        max_bytes: Optional[Int] = none
    ) -> Result[Optional[Bytes], FileSystemError]
    # Writes the UTF-8 text at the current position; errors can leave a prefix. Does not truncate or reposition this handle.
    def write(data: String) -> Result[Unit, FileSystemError]
    # Writes all bytes at the current position, with the same rules as write.
    def write_bytes(data: Bytes) -> Result[Unit, FileSystemError]
    # Writes text at the current position; appends only when the handle was opened in append mode.
    def append_file(data: String) -> Result[Unit, FileSystemError]
    # Writes bytes at the current position; appends only when the handle was opened in append mode.
    def append_file_bytes(data: Bytes) -> Result[Unit, FileSystemError]
    # Reads at a nonnegative byte offset without moving the position; short/empty Bytes mark EOF.
    def read_at(
        offset: Int,
        max_bytes: Optional[Int] = none
    ) -> Result[Bytes, FileSystemError]
    # Writes the UTF-8 text at a nonnegative offset without moving the position; errors can leave a prefix.
    def write_at(offset: Int, data: String) -> Result[Unit, FileSystemError]
    # Writes all bytes at a nonnegative offset without moving the position; errors can leave a prefix.
    def write_at_bytes(offset: Int, data: Bytes) -> Result[Unit, FileSystemError]
    # Reads remaining bytes from the current position; EOF returns empty Bytes.
    def read_file(max_bytes: Optional[Int] = none) -> Result[Bytes, FileSystemError]
    # Reads consecutive buffers of the given `sizes` in bytes, each up to 65536 and all together up to 16 MiB, and returns the bytes obtained for each.
    # `offset` -1 reads from the current position; other offsets read without moving it. A buffer is shorter than requested at end of file. A negative size or offset below -1 returns InvalidInput.
    def read_vectors(
        sizes: List[Int],
        offset: Int
    ) -> Result[List[Bytes], FileSystemError]
    # Writes every buffer; offset -1 uses the current position.
    def write_vectors(
        buffers: List[Bytes],
        offset: Int
    ) -> Result[Unit, FileSystemError]
    # Seeks in bytes with origin exactly 0 (start), 1 (current), or 2 (end).
    # Other origins return InvalidInput; the OS validates the resulting offset.
    def seek(offset: Int, origin: Int) -> Result[Int, FileSystemError]
    # Returns metadata for the open file.
    def stat() -> Result[FileInfo, FileSystemError]
    # Sets the file length to `size` bytes, discarding the excess or extending with zero bytes. The current position is not moved.
    # A negative size returns InvalidInput.
    def truncate(size: Int) -> Result[Unit, FileSystemError]
    # Flushes the file's data and metadata to stable storage.
    def sync() -> Result[Unit, FileSystemError]
    # Flushes the file's data to stable storage, skipping metadata that is not needed to read it back where the host allows.
    # Hosts without a separate data sync perform a full sync.
    def data_sync() -> Result[Unit, FileSystemError]
    # Sets the permission bits of the open file to `mode` (0 through 4095).
    def chmod(mode: Int) -> Result[Unit, FileSystemError]
    # Sets the owner and group of the open file by numeric id; -1 leaves that id unchanged. Usually needs privilege.
    def chown(uid: Int, gid: Int) -> Result[Unit, FileSystemError]
    # Sets the access and modification times of the open file. Returns Unsupported on hosts without descriptor timestamps.
    def set_times(
        accessed: Timestamp,
        modified: Timestamp
    ) -> Result[Unit, FileSystemError]
    # Reads from the current position to the end and returns the lines with their `\n` or `\r\n` terminators removed.
    # Invalid UTF-8 returns InvalidData, and more bytes than `max_bytes` or lines than `max_lines` returns LimitExceeded.
    def read_lines(
        max_bytes: Optional[Int] = none,
        max_lines: Optional[Int] = none
    ) -> Result[List[String], FileSystemError]

# An open directory that yields one child per read and must be closed.
export interface Directory:
    # Returns the path this cursor was opened with.
    def path() -> String
    # Releases the directory handle.
    # Safe to call repeatedly; later reads return Closed.
    def close() -> Unit
    # Returns the next child in native directory order, or none after the last one.
    # The order is not sorted.
    def read() -> Result[Optional[DirectoryEntry], FileSystemError]

# A change stream returned by a filesystem watch operation.
export interface FileWatcher:
    # Stops the watcher, wakes a pending `next` with Closed, and waits for its worker to stop.
    # Safe to call repeatedly.
    def close() -> Unit
    # Waits for filesystem activity and returns events. A native watcher returns one event per call; a polling watcher returns every difference seen after an interval.
    # Cancelling the waiting task unwinds it, and a closed watcher returns Closed. A native watcher that overflowed with policy `error` returns LimitExceeded.
    def next() -> Result[List[FileEvent], FileSystemError]

# A temporary directory whose contents are removed when it is closed.
export interface TemporaryDirectory:
    # Removes the directory and everything inside it.
    # Safe to call repeatedly.
    def close() -> Unit
    # Returns the absolute path of the directory, created under the host's temporary root.
    def path() -> String

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
export def constants() -> Map[String, Int]: ...

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
    def message() -> String: ...

# Returns filesystem operations for the current host.
export def filesystem() -> FileSystem: ...

# Errors returned when a path cannot be parsed or resolved.
export type PathError:
    # Invalid NUL input, a nonabsolute resolve/relative anchor or malformed glob syntax.
    case InvalidInput

# Returns the final path component, excluding trailing separators.
export def basename(path: String) -> String: ...

# Returns the directory portion of a path.
export def dirname(path: String) -> String: ...

# Returns the final extension, including its leading dot, or an empty string.
export def extension(path: String) -> String: ...

# Reports whether a path is absolute according to the host path rules.
export def is_absolute(path: String) -> Bool: ...

# Joins path parts using the host separator and normalizes the result.
export def join(parts: List[String]) -> String: ...

# Normalizes separators and dot segments without accessing the filesystem.
export def normalize(path: String) -> String: ...

# Computes a relative path from `base` to `target` using host path rules.
export def relative(base: String, target: String) -> Result[String, PathError]: ...

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
    def basename(path: String) -> String
    # Removes an exact suffix under basename compatibility rules; it does not strip arbitrary extensions.
    def basename_without(path: String, suffix: String) -> String
    # Returns the directory component using the selected POSIX or Windows convention.
    def dirname(path: String) -> String
    # Returns the final dot extension, or empty text for extensionless names and simple dotfiles.
    def extension(path: String) -> String
    # Tests absolute-root syntax; a Windows drive-relative spelling is not absolute.
    def is_absolute(path: String) -> Bool
    # Joins nonempty parts and normalizes separators/dot segments without filesystem access.
    def join(parts: List[String]) -> String
    # Cleans repeated separators and dot segments lexically; it does not resolve symlinks.
    def normalize(path: String) -> String
    # Computes a lexical relative path from absolute anchors; different roots return the original target.
    # Nonabsolute anchors or invalid NUL input return InvalidInput.
    def relative(base: String, target: String) -> Result[String, PathError]
    # Resolves parts against an explicit absolute base; no process working directory is consulted.
    def resolve(base: String, parts: List[String]) -> Result[String, PathError]
    # Splits the original spelling into root, directory, base, extension and name without filesystem access.
    def parse(path: String) -> PathParts
    # Builds a path with directory preferred over root, and base preferred over name plus extension.
    def format(parts: PathParts) -> String
    # Returns slash for POSIX or backslash for Windows path components.
    def separator() -> String
    # Returns colon for POSIX or semicolon for Windows path-list entries.
    def delimiter() -> String
    # Returns a Windows namespaced absolute path when applicable; POSIX paths are unchanged.
    def to_namespaced_path(path: String) -> String
    # Tests one lexical path against the supported glob syntax; malformed patterns return InvalidInput.
    def matches_glob(path: String, pattern: String) -> Result[Bool, PathError]

# Returns path operations using POSIX separators and parsing rules.
export def posix() -> PathOperations: ...

# Returns path operations using Windows separators and parsing rules.
export def win32() -> PathOperations: ...

# Returns the basename with the supplied suffix removed when it matches.
export def basename_without(path: String, suffix: String) -> String: ...

# Resolves path parts against a base using host path conventions.
export def resolve(base: String, parts: List[String]) -> Result[String, PathError]: ...

# Splits a path into its root, directory, base, extension, and name.
export def parse(path: String) -> PathParts: ...

# Formats parsed path components as a path string.
export def format(parts: PathParts) -> String: ...

# Returns the host's path separator.
export def separator() -> String: ...

# Returns the host's path-list delimiter.
export def delimiter() -> String: ...

# Converts a path to the host's namespaced representation when applicable.
export def to_namespaced_path(path: String) -> String: ...

# Tests a path against a glob pattern.
export def matches_glob(path: String, pattern: String) -> Result[Bool, PathError]: ...

impl Error for PathError:
    # Returns a path-prefixed diagnostic without revealing the supplied paths or pattern.
    def message() -> String: ...
