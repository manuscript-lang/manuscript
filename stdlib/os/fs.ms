/*
Files and directories.

Completion rule: an operation on a whole file's contents (`read_file`, `write_file`, `append_file`,
`write_atomic`) returns a `Promise` that is already running, so it can overlap other work; every other call
(metadata, directories, links, handles, copy, move, glob) blocks and returns `T!`.
Text and bytes use one function: `write_file(path, "text")` and `write_file(path, bytes)` both type-check.
Functions take at most three parameters; more settings travel in an `*Options` record.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
import read_file, write_file from "@std/os/fs.ms"

try write_file("notes.txt", "hello").wait()
data := try read_file("notes.txt").wait()
```
*/
import (
	Bytes from "@std/bytes.ms",
	Promise, adopt, owned_task from "@std/concurrency/promise.ms",
	Closeable, Writable from "@std/core.ms",
	ReadStream, Sink, Source, WriteStream from "@std/io/io.ms",
	BigInt from "@std/math/math.ms",
	Duration, Timestamp, milliseconds, monotonic, now, sleep from "@std/time.ms",

	msstd_fs_access,
	msstd_fs_admit,
	msstd_fs_append_file,
	msstd_fs_canonicalize,
	msstd_fs_chmod,
	msstd_fs_chown,
	msstd_fs_create_directory,
	msstd_fs_create_link,
	msstd_fs_directory_close,
	msstd_fs_directory_open,
	msstd_fs_directory_path,
	msstd_fs_directory_read,
	msstd_fs_file_chmod,
	msstd_fs_file_chown,
	msstd_fs_file_clone,
	msstd_fs_file_data_sync,
	msstd_fs_file_read_at,
	msstd_fs_file_read_file,
	msstd_fs_file_read_lines,
	msstd_fs_file_read_vectors,
	msstd_fs_file_seek,
	msstd_fs_file_set_times,
	msstd_fs_file_stat,
	msstd_fs_file_sync,
	msstd_fs_file_truncate,
	msstd_fs_file_try_lock,
	msstd_fs_file_unlock,
	msstd_fs_file_write_at,
	msstd_fs_file_write_vectors,
	msstd_fs_filesystem,
	msstd_fs_hard_link,
	msstd_fs_list,
	msstd_fs_open,
	msstd_fs_read_file,
	msstd_fs_read_link,
	msstd_fs_release,
	msstd_fs_remove,
	msstd_fs_rename,
	msstd_fs_set_times,
	msstd_fs_stat,
	msstd_fs_stat_filesystem,
	msstd_fs_temporary_close,
	msstd_fs_temporary_directory,
	msstd_fs_temporary_open,
	msstd_fs_temporary_path,
	msstd_fs_temporary_root,
	msstd_fs_truncate,
	msstd_fs_watch,
	msstd_fs_watch_close,
	msstd_fs_watch_native,
	msstd_fs_watch_next,
	msstd_fs_write_file,
	msstd_io_close,
	msstd_io_read,
	msstd_io_write,
	msstd_io_write_bytes from "@std/internal/fs.ms",
	msrt_promise_finished from "@std/internal/promises.ms",
)

// The name and kind flags for one child returned by a directory listing.
export type DirectoryEntry:
	// The child's file name only, without any directory part, in the host's spelling.
	name: String
	// True when the child is a directory; a symbolic link is reported by `symlink`, not
	// as a directory.
	directory: Bool
	// True when the child itself is a symbolic link, whatever it points to.
	symlink: Bool

// What kind of filesystem object an entry is.
export enum FileKind:
	// An ordinary file holding bytes.
	File
	// A directory that lists child entries.
	Directory
	// A symbolic link itself (only reported when links are not followed).
	Symlink
	// A named pipe (FIFO) used for inter-process byte streams.
	Fifo
	// A Unix domain socket file.
	Socket
	// A block special device.
	BlockDevice
	// A character special device.
	CharDevice

// How `open` treats the file.
export enum OpenMode:
	// Read an existing file.
	Read
	// Read and write an existing file.
	ReadWrite
	// Write, creating the file or truncating it.
	Write
	// Read and write, creating the file or truncating it.
	WriteRead
	// Write at the end, creating the file when absent.
	Append
	// Read and write at the end, creating the file when absent.
	AppendRead

// Settings of `open` beyond the mode.
export type OpenOptions:
	// When True, creating a file that already exists returns EEXIST. Applies to
	// `Write`, `WriteRead`, `Append` and `AppendRead`.
	exclusive: Bool = false
	// Permission bits 0..4095 given to a created file, subject to umask and OS policy.
	permissions: Int = 438

// The position a `seek` offset counts from.
export enum Seek:
	// The start of the file.
	Start
	// The handle's current position; the offset is relative to it and may be negative.
	Current
	// The end of the file.
	End

// File metadata, including portable fields and exact platform-specific numeric values.
export type FileInfo:
	// The final path component's file name only.
	name: String
	// File length in bytes.
	size: Int
	// What the entry is. A symbolic link is `Symlink` only when links were not
	// followed.
	kind: FileKind
	// Time the file's contents were last changed.
	modified: Timestamp
	// Time the file was last read; it falls back to `modified` where the host lacks
	// access times.
	accessed: Timestamp
	// Time the file's metadata or contents last changed; it falls back to `modified`
	// where the host lacks it.
	changed: Timestamp
	// POSIX mode bits: the file-type bits such as 0100000 for a regular file, plus
	// permission and setuid, setgid, and sticky bits.
	mode: Int
	// Only the permission, setuid, setgid, and sticky bits of `mode`, 0 through 4095.
	permissions: Int
	// Birth time of the file, or none when the host or filesystem does not record it.
	created: Timestamp?
	// Preferred I/O block size in bytes; unavailable fields are zero.
	block_size: Int
	// Allocated 512-byte blocks on POSIX hosts; unavailable fields are zero.
	blocks: Int
	// Device id the entry represents when it is a device file, otherwise 0.
	rdev: Int
	// Unbounded copies of the numeric fields `size`, `mode`, `device`, `inode`,
	// `links`, `uid`, `gid`, `block_size`, `blocks`, and `rdev`, which cannot overflow,
	// plus the times as nanoseconds since the Unix epoch under `accessed_ns`,
	// `modified_ns`, `changed_ns`, and `created_ns`. Unavailable values are 0.
	exact: Map[String, BigInt]
	// Id of the device that holds the file; with `inode` it identifies the file. 0
	// where unavailable.
	device: Int
	// The file's index number on its device; 0 where unavailable.
	inode: Int
	// Number of hard links to the file; 0 where unavailable.
	links: Int
	// Numeric id of the owning user; 0 where unavailable.
	uid: Int
	// Numeric id of the owning group; 0 where unavailable.
	gid: Int

impl FileInfo:
	// True for an ordinary file.
	fn is_file() Bool:
		return self.kind == FileKind.File

	// True for a directory.
	fn is_directory() Bool:
		return self.kind == FileKind.Directory

	// True for a symbolic link itself, which only happens when links were not followed.
	fn is_symlink() Bool:
		return self.kind == FileKind.Symlink

// The directory walks that run natively, so the runtime can call the caller's predicate
// closures.
interface FileSystem:
	// Returns entries matching the supplied include and exclude patterns.
	fn glob(
		path: String,
		options: GlobOptions,
		exclude: (fn(PathEntry) Bool)?
	) List[PathEntry]!
	// Copies a file or tree according to the flattened replacement and size policies of
	// `copy`.
	fn copy(
		source: String,
		destination: String,
		options: NativeCopyOptions,
		filter: (fn(String, String) Bool)?
	) Unit!

// The runtime handle behind a `FileHandle`.
export extern type NativeFile

// An open file supporting sequential and positional I/O. It owns its descriptor:
// `close` it, or let its binding go out of scope.
export opaque type FileHandle:
	// The runtime handle for the open file; it is released by `close` and owned by this
	// value.
	native: NativeFile

impl Closeable for FileHandle:
	// Closes the file, interrupts calls in progress, and waits for them to stop.
	// Safe to call repeatedly; later operations return EBADF.
	var fn close() Unit!:
		return msstd_io_close(self.native)

impl FileHandle:
	/*
    Returns a second handle over a duplicate of the file's descriptor, which closes on its own.
    Both share the file position, so a read or write through one moves the other; bytes this handle already read ahead stay with it.
    A closed handle returns EBADF.
    */
	fn clone() FileHandle!:
		return msstd_fs_file_clone(self.native)

	// Duplicates this handle for chunk reads; the stream closes its own descriptor
	// independently and shares the file position.
	fn reader() ReadStream[Bytes]!:
		own := try self.clone()
		return ok(ReadStream[Bytes](FileSource(own)))

	// Adapts complete writes to `Error`/Unit; flush synchronizes the file.
	fn writer() WriteStream[Bytes]!:
		own := try self.clone()
		return ok(WriteStream[Bytes](FileSink(own)))

	// Returns a positive chunk (at most 64 KiB), or none at EOF; a supplied size must
	// be positive.
	fn read(max_bytes: Int?) Bytes?!:
		return msstd_io_read(self.native, max_bytes)

	// Writes all of `data` (text as UTF-8) at the current position; errors can leave a
	// prefix. Does not truncate or reposition this handle. Writes at the end only when
	// the handle was opened in an append mode.
	fn write(data: Writable) Unit!:
		return msstd_io_write_bytes(self.native, data.as_bytes())

	// Reads at a nonnegative byte offset without moving the position; short/empty Bytes
	// mark EOF.
	fn read_at(offset: Int, max_bytes: Int?) Bytes!:
		return msstd_fs_file_read_at(self.native, offset, max_bytes)

	// Writes all of `data` (text as UTF-8) at a nonnegative offset without moving the
	// position; a handle opened for append returns EINVAL because the host would ignore
	// the offset; errors can leave a prefix.
	fn write_at(offset: Int, data: Writable) Unit!:
		return msstd_fs_file_write_at(self.native, offset, data.as_bytes())

	// Reads remaining bytes from the current position; EOF returns empty Bytes.
	fn read_file(max_bytes: Int?) Bytes!:
		return msstd_fs_file_read_file(self.native, max_bytes)

	// Reads consecutive buffers of the given `sizes` in bytes, each up to 65536 and all
	// together up to 16 MiB, and returns the bytes obtained for each.
	// `offset` -1 reads from the current position; other offsets read without moving it. A buffer is shorter than requested at end of file. A negative size or offset below -1 returns EINVAL.
	fn read_vectors(sizes: List[Int], offset: Int) List[Bytes]!:
		return msstd_fs_file_read_vectors(self.native, sizes, offset)

	// Writes every buffer; offset -1 uses the current position. A nonnegative offset on
	// a handle opened for append returns EINVAL.
	fn write_vectors(buffers: List[Bytes], offset: Int) Unit!:
		return msstd_fs_file_write_vectors(self.native, buffers, offset)

	// Moves the position to `offset` bytes from `origin` and returns the new position;
	// the OS validates the resulting offset.
	fn seek(offset: Int, origin: Seek = Seek.Start) Int!:
		return msstd_fs_file_seek(self.native, offset, seek_origin(origin))

	// Returns metadata for the open file.
	fn stat() FileInfo!:
		return msstd_fs_file_stat(self.native)

	// Sets the file length to `size` bytes, discarding the excess or extending with
	// zero bytes. The current position is not moved. A negative size returns EINVAL.
	fn truncate(size: Int) Unit!:
		return msstd_fs_file_truncate(self.native, size)

	// Flushes the file's data and metadata to stable storage.
	fn sync() Unit!:
		return msstd_fs_file_sync(self.native)

	// Flushes the file's data to stable storage, skipping metadata that is not needed
	// to read it back where the host allows. Hosts without a separate data sync perform
	// a full sync.
	fn data_sync() Unit!:
		return msstd_fs_file_data_sync(self.native)

	/*
    Tries to take an advisory lock on the whole file without waiting: shared (many readers) or `exclusive` (one writer).
    Returns False when another handle holds a conflicting lock. The lock is advisory: it only excludes other lockers (`flock` on Unix, `LockFileEx` on Windows), and closing the handle releases it.
    Handles made by `clone` share one lock, and locking a handle that already holds one converts it. A closed handle returns EBADF.
    */
	fn try_lock(exclusive: Bool) Bool!:
		taken := try msstd_fs_file_try_lock(self.native, exclusive)
		return ok(taken == 1)

	// Takes an advisory lock like `try_lock`, retrying every few milliseconds for up to
	// `timeout`; none waits until it is granted. Returns False when the timeout passes
	// first. The wait is a cancellable sleep, so task cancellation ends it.
	fn lock(exclusive: Bool, timeout: Duration?) Bool!:
		started := monotonic()

		while true:
			if try self.try_lock(exclusive): return ok(true)

			if limit := timeout:
				if monotonic().difference(started).compare(limit) >= 0: return ok(false)
			try sleep(milliseconds(5)).wait()

		return ok(false)

	// Releases the advisory lock this handle holds; releasing when none is held
	// succeeds.
	fn unlock() Unit!:
		return msstd_fs_file_unlock(self.native)

	// Sets the permission bits of the open file to `mode` (0 through 4095).
	fn chmod(mode: Int) Unit!:
		return msstd_fs_file_chmod(self.native, mode)

	// Sets the owner and group of the open file by numeric id; -1 leaves that id
	// unchanged. Usually needs privilege.
	fn chown(uid: Int, gid: Int) Unit!:
		return msstd_fs_file_chown(self.native, uid, gid)

	// Sets the access and modification times of the open file. Returns ENOTSUP on hosts
	// without descriptor timestamps.
	fn set_times(accessed: Timestamp, modified: Timestamp) Unit!:
		return msstd_fs_file_set_times(self.native, accessed, modified)

	// Reads from the current position to the end and returns the lines with their `\n`
	// or `\r\n` terminators removed. Invalid UTF-8 returns EBADMSG, and more bytes than
	// `max_bytes` or lines than `max_lines` returns EOVERFLOW. A negative `max_bytes`
	// or `max_lines` returns EINVAL.
	fn read_lines(max_bytes: Int?, max_lines: Int?) List[String]!:
		return msstd_fs_file_read_lines(self.native, max_bytes, max_lines)

// Chunks of a file from its current position, until the end.
type FileSource:
	file: FileHandle

impl Source[Bytes] for FileSource:
	var fn next() Bytes?!:
		return self.file.read(none)

	var fn close() Unit!:
		return self.file.close()

// Complete writes to a file; `flush` synchronizes it.
type FileSink:
	file: FileHandle

impl Sink[Bytes] for FileSink:
	var fn write(value: Bytes) Unit!:
		return self.file.write(value)

	var fn flush() Unit!:
		return self.file.sync()

	var fn close() Unit!:
		return self.file.close()

fn seek_origin(origin: Seek) Int:
	match origin:
		Start: return 0
		Current: return 1
		End: return 2

// The runtime handle behind a `Directory`.
export extern type NativeDirectory

// An open directory that yields one child per read and must be closed.
export opaque type Directory:
	// The runtime handle for the open directory; it is released by `close` and owned by
	// this value.
	native: NativeDirectory

impl Closeable for Directory:
	// Releases the directory handle.
	// Safe to call repeatedly; later reads return EBADF.
	// Closes the directory; further reads fail with a closed error.
	var fn close() Unit!:
		msstd_fs_directory_close(self.native)

impl Directory:
	// Returns the path this cursor was opened with.
	fn path() String:
		return msstd_fs_directory_path(self.native)

	// Returns the next child in native directory order, or none after the last one.
	// The order is not sorted.
	fn read() DirectoryEntry?!:
		return msstd_fs_directory_read(self.native)

// A directory is a stream source: `ReadStream[DirectoryEntry](open_directory(path))`
// yields its children in native order, so steps compose:
// `... | filter(...) | collect(none)`. Closing the stream closes the directory.
impl Source[DirectoryEntry] for Directory:
	// The next child entry, or none after the last one; the order is the native
	// directory order.
	var fn next() DirectoryEntry?!:
		return msstd_fs_directory_read(self.native)

	// Closes the directory; further reads fail with a closed error.
	var fn close() Unit!:
		msstd_fs_directory_close(self.native)

// The runtime handle behind a `FileWatcher`.
export extern type NativeWatcher

// The native watcher a watch operation returns; `watch` wraps it into a stream.
export opaque type RawWatcher:
	// The runtime handle for the watch; the stream releases it when it closes.
	native: NativeWatcher

// Events one native call returned and the reader has not taken yet, newest first so
// `pop` moves the next one out.
type WatchSource:
	watcher: RawWatcher
	pending: List[FileEvent]

impl Source[FileEvent] for WatchSource:
	// Waits for the next change. A closed watcher is `EBADF`; a native watcher that
	// overflowed with policy `error` is `EOVERFLOW`.
	var fn next() FileEvent?!:
		while true:
			if event := self.pending.pop(): return ok(event)

			var batch = try msstd_fs_watch_next(self.watcher.native)
			batch.reverse()
			self.pending = batch

		return ok(none)

	// Stops the watcher and waits for its worker to stop.
	var fn close() Unit!:
		msstd_fs_watch_close(self.watcher.native)

fn watch_stream(watcher: RawWatcher) ReadStream[FileEvent]:
	return ReadStream[FileEvent](WatchSource(watcher, []))

// The runtime handle behind a `TemporaryDirectory`.
export extern type NativeTemporary

// A temporary directory whose contents are removed when it is closed.
export opaque type TemporaryDirectory:
	// The runtime handle for the directory; it is released by `close` and owned by this
	// value.
	native: NativeTemporary

impl Closeable for TemporaryDirectory:
	// Removes the directory and everything inside it.
	// Safe to call repeatedly.
	var fn close() Unit!:
		_ := msstd_fs_temporary_close(self.native)

impl TemporaryDirectory:
	// Returns the absolute path of the directory, created under the host's temporary
	// root.
	fn path() String:
		return msstd_fs_temporary_path(self.native)

// One filesystem change and the affected path.
export type FileEvent:
	// Path of the affected entry, formed from the watched path plus any child
	// components.
	path: String
	// Exactly `rename` (appearance/disappearance/rename) or `change`
	// (contents/metadata).
	kind: String

// Capacity/free-space statistics: block_size is bytes, blocks/free/available are counts
// in those blocks, and files/files_free are native file-node counts (zero if
// unavailable).
export type FileSystemInfo:
	// The host's numeric filesystem type code, such as the magic number reported by
	// Linux; 0 where unavailable.
	type_id: Int
	// Size in bytes of the blocks that `blocks`, `blocks_free`, and `blocks_available`
	// count.
	block_size: Int
	// Total number of blocks in the filesystem.
	blocks: Int
	// Number of unused blocks, including space reserved for privileged users.
	blocks_free: Int
	// Number of unused blocks available to unprivileged users.
	blocks_available: Int
	// Total number of file nodes, such as inodes, the filesystem can hold; 0 where
	// unavailable.
	files: Int
	// Number of unused file nodes; 0 where unavailable.
	files_free: Int

// Whether a copy asks the filesystem to clone file data (copy-on-write) instead of
// copying bytes.
export enum CloneMode:
	// Always copy the bytes; never ask the filesystem to clone.
	Off
	// Clone when the filesystem can, otherwise copy bytes.
	Prefer
	// Require a native clone; fail when the filesystem cannot.
	Require

// Policies for recursive copies, including replacement, symlinks, and optional limits.
export type CopyOptions:
	// When True, directories are copied with their contents; when False, a directory
	// source returns EINVAL.
	recursive: Bool = false
	// When True, an existing destination file or link is replaced; when False, an
	// existing destination returns EEXIST.
	replace: Bool = false
	// When True, symbolic links are followed and their targets copied; when False,
	// links are recreated as links.
	dereference: Bool = false
	// When True, copied files and directories keep the source's access and modification
	// times.
	preserve_timestamps: Bool = false
	// When True, a copied link keeps its target text unchanged. When False, a relative
	// target is rewritten relative to the source directory so it still reaches the
	// original file.
	verbatim_symlinks: Bool = false
	// Whether to clone file data natively instead of copying bytes.
	clone: CloneMode = CloneMode.Off
	// Most files, directories, and links visited, counting the root. Exceeding it
	// returns EOVERFLOW. none sets no limit.
	max_entries: Int? = none
	// Most file bytes copied in total. Exceeding it returns EOVERFLOW. none sets no
	// limit.
	max_bytes: Int? = none
	// Called with each source and destination path; the entry is skipped when it
	// returns False. none copies everything.
	filter: (fn(String, String) Bool)? = none

// `CopyOptions` as the native walk reads it: `clone` as text and the replacement policy as two flags.
type NativeCopyOptions:
	recursive: Bool
	replace: Bool
	error_on_exists: Bool
	dereference: Bool
	preserve_timestamps: Bool
	verbatim_symlinks: Bool
	clone: String
	max_entries: Int?
	max_bytes: Int?

/*
How `watch` observes a path: with native OS events by default, or by polling snapshots when `interval` is set.
Every field has a default, so `WatchOptions()` watches natively with no limits and `WatchOptions(interval: seconds(1))` polls.
`max_events` and `overflow` apply only to native watching; combining them with `interval` returns `EINVAL`.
*/
export type WatchOptions:
	// Polling period, which must be positive. none watches with native OS events.
	interval: Duration? = none
	// Most paths under the root, counted when the watcher starts. Exceeding it returns
	// EOVERFLOW. none sets no limit.
	max_entries: Int? = none
	// Most queued native events. Native watchers only. none sets no limit.
	max_events: Int? = none
	// What a native watcher does when its queue overflows: exactly `error` (default) or
	// `ignore`. Native watchers only.
	overflow: String? = none

// A matched path together with its filesystem entry metadata.
export type PathEntry:
	// The matched path relative to the glob root, always `/`-separated.
	path: String
	// The directory entry record for the match: name, directory flag, and symlink flag.
	entry: DirectoryEntry

// Include and exclude patterns and limits used by filesystem glob operations.
export type GlobOptions:
	// Glob patterns to include; an entry that matches any of them is returned.
	patterns: List[String]
	// Glob patterns for entries to skip; a match is neither returned nor searched
	// further.
	exclude: List[String] = []
	// When True, symbolic links to directories are traversed, with cycles detected;
	// when False, links are reported but not entered.
	follow_links: Bool = false
	// Most filesystem entries visited while searching. Exceeding it returns EOVERFLOW.
	// none sets no limit.
	max_entries: Int? = none
	// Most distinct matches returned. Exceeding it returns EOVERFLOW. none sets no
	// limit.
	max_results: Int? = none

// The filesystem of the current host.
fn host() FileSystem:
	return msstd_fs_filesystem()

/*
Returns entries matching the include patterns of `options`, sorted by path. `path` is the root; each result's
`path` is relative to it and always `/`-separated. `exclude` skips an entry (and does not enter a skipped directory) when it
returns True. A malformed pattern, one over 4096 bytes, or a negative limit returns EINVAL.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
sources := try glob(".", GlobOptions(patterns: ["*.ms"]))
```
*/
// ms: effect std.fs.read
export fn glob(
	path: String,
	options: GlobOptions,
	exclude: (fn(PathEntry) Bool)? = none
) List[PathEntry]!:
	return host().glob(path, options, exclude)

fn clone_text(mode: CloneMode) String:
	match mode:
		Off: return "none"
		Prefer: return "try"
		Require: return "force"

/*
Copies a file or, with `options.recursive`, a directory tree.
By default an existing destination returns EEXIST; set `replace` to overwrite it. `options.filter` is called with each
source and destination path and skips the entry when it returns False.
Entry and byte limits apply cumulatively across the whole copy.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
try copy("a.txt", "b.txt", CopyOptions(replace: true))
```
*/
// ms: effect std.fs.read
// ms: effect std.fs.write
export fn copy(
	source: String,
	destination: String,
	options: CopyOptions = CopyOptions()
) Unit!:
	native := NativeCopyOptions(
		recursive: options.recursive, replace: options.replace, error_on_exists: true,
		dereference: options.dereference,
		preserve_timestamps: options.preserve_timestamps,
		verbatim_symlinks: options.verbatim_symlinks, clone: clone_text(options.clone),
		max_entries: options.max_entries, max_bytes: options.max_bytes
	)
	return host().copy(source, destination, native, options.filter)

// Resolves symlinks and returns the canonical absolute path.
// ms: effect std.fs.read
export fn canonicalize(path: String) String!:
	return msstd_fs_canonicalize(path)

// Creates one directory; recursive defaults to False, requiring its parent to exist.
// ms: effect std.fs.write
export fn create_directory(path: String, recursive: Bool = false) Unit!:
	return msstd_fs_create_directory(path, recursive)

// Creates a symbolic link at `path` pointing to `target`.
// ms: effect std.fs.write
export fn create_symlink(path: String, target: String) Unit!:
	return msstd_fs_create_link(path, target)

// Lists a directory, optionally limiting the number of returned entries. A name that is
// not valid UTF-8 is listed with U+FFFD in place of each invalid byte, so it no longer
// addresses the entry. The same holds for `glob`, `stat` names and directory cursors.
// ms: effect std.fs.read
export fn list(path: String, max_entries: Int? = none) List[DirectoryEntry]!:
	return msstd_fs_list(path, max_entries)

// A slot among the few in-flight copies of large write payloads. The blocking pool has
// a few threads, so a caller that would copy a large payload parks until a slot is free
// instead of piling copies up; closing it frees the slot.
type WritePermit:
	held: Bool

impl Closeable for WritePermit:
	var fn close() Unit!:
		if self.held:
			self.held = false
			msstd_fs_release()

fn already_exists() Error:
	return Error("filesystem: already exists", kind: "EEXIST")

fn invalid_input() Error:
	return Error("filesystem: invalid input", kind: "EINVAL")

// Starts reading a file fully into memory and returns its promise. Supply `max_bytes`
// for untrusted or large files.
// ms: effect std.fs.read
export fn read_file(path: String, max_bytes: Int? = none) Promise[Bytes]:
	return owned_task[Bytes](read_job(path.clone(), max_bytes))

// The work of `read_file`: a returned closure owns its captures, so the promise borrows
// nothing.
fn read_job(path: String, max_bytes: Int?) fn() Bytes!:
	return fn: msstd_fs_read_file(path, max_bytes)

// Returns the target text stored in the symbolic link at `path`, without resolving it.
// A path that is not a link returns EINVAL.
// ms: effect std.fs.read
export fn read_symlink(path: String) String!:
	return msstd_fs_read_link(path)

// Removes a file or empty directory; recursive defaults to False, retaining nonempty
// trees. A missing path returns ENOENT, except that a recursive removal of a missing
// path succeeds.
// ms: effect std.fs.delete
export fn remove(path: String, recursive: Bool = false) Unit!:
	return msstd_fs_remove(path, recursive)

// Moves `source` to `destination` using the operating system's rename, applying its
// rules for replacing an existing destination. It never falls back to copying, so a
// move across devices returns an error.
// ms: effect std.fs.write
// ms: effect std.fs.delete
export fn rename(source: String, destination: String) Unit!:
	return msstd_fs_rename(source, destination)

// Returns metadata for `path`. `follow_links` True (the default) describes the link
// target and False describes the link itself.
// ms: effect std.fs.read
export fn stat(path: String, follow_links: Bool = true) FileInfo!:
	return msstd_fs_stat(path, follow_links)

// Queries the host temp root without creating or checking a directory.
// ms: effect std.fs.read
export fn temporary_root() String!:
	return ok(msstd_fs_temporary_root())

// Creates a new directory under the host temp root; the caller must remove it.
// Prefix must be nonempty and contain no slash, backslash, or NUL.
// ms: effect std.fs.write
export fn temporary_directory(prefix: String) String!:
	return msstd_fs_temporary_directory(prefix)

// Starts creating a file exclusively and returns its promise; replace defaults to
// False, retaining an existing file.
// `data` is text (written as UTF-8) or `Bytes`.
// ms: effect std.fs.write
export fn write_file(path: String, data: Writable, replace: Bool = false) Promise[Unit]:
	payload := data.as_bytes()
	held := msstd_fs_admit(payload.length())
	return owned_task[Unit](write_job(path.clone(), payload, replace, held))

// The work of `write_file`. The task runs at once, so the slot frees the moment the
// write ends, not when the promise is dropped: `permit` is a local that closes at the
// end of the closure.
fn write_job(path: String, data: Bytes, replace: Bool, held: Bool) fn() Unit!:
	return fn:
		permit := WritePermit(held: held)
		return msstd_fs_write_file(path, data, replace)

// Checks access with mode 0..7: existence 0, read 4, write 2, execute 1, or combined
// bits. Native permissions and Windows access policy still apply.
// ms: effect std.fs.read
export fn access(path: String, mode: Int) Unit!:
	return msstd_fs_access(path, mode)

// Starts appending `data` (text or `Bytes`) to the end of the file and returns its
// promise, creating the file with mode 0600 when absent. Writes every byte or fails,
// possibly leaving a partial append.
// ms: effect std.fs.write
export fn append_file(path: String, data: Writable) Promise[Unit]:
	payload := data.as_bytes()
	held := msstd_fs_admit(payload.length())
	return owned_task[Unit](append_job(path.clone(), payload, held))

fn append_job(path: String, data: Bytes, held: Bool) fn() Unit!:
	return fn:
		permit := WritePermit(held: held)
		return msstd_fs_append_file(path, data)

// Changes target permissions with mode 0..4095. `follow_links` True (the default)
// follows a final symbolic link; False changes the link itself, which returns ENOTSUP
// on hosts lacking this operation.
// ms: effect std.fs.write
export fn chmod(path: String, mode: Int, follow_links: Bool = true) Unit!:
	return msstd_fs_chmod(path, mode, follow: follow_links)

// Sets the owning user and group of `path` by numeric id; -1 leaves that id unchanged.
// `follow_links` True (the default) follows a final symbolic link; False changes the link itself, with ENOTSUP on hosts lacking this operation.
// Usually needs privilege, and Windows returns ENOTSUP.
// ms: effect std.fs.write
export fn chown(path: String, uid: Int, gid: Int, follow_links: Bool = true) Unit!:
	return msstd_fs_chown(path, uid, gid, follow: follow_links)

// Sets the target size in bytes; follows a final symbolic link.
// ms: effect std.fs.write
export fn truncate(path: String, size: Int) Unit!:
	return msstd_fs_truncate(path, size)

// Sets the access and modification times of `path`. `follow_links` True (the default)
// follows a final symbolic link; False updates the link itself, with ENOTSUP where the
// host lacks it, such as Windows.
// ms: effect std.fs.write
export fn set_times(
	path: String,
	accessed: Timestamp,
	modified: Timestamp,
	follow_links: Bool = true
) Unit!:
	return msstd_fs_set_times(path, accessed, modified, follow: follow_links)

// Creates `destination` as another name for the file at `source`. An existing
// destination returns EEXIST; it must be on the same filesystem as `source`.
// ms: effect std.fs.write
export fn create_hard_link(source: String, destination: String) Unit!:
	return msstd_fs_hard_link(source, destination)

// The runtime's mode text: `x` after the first letter makes creation exclusive.
fn open_flags(mode: OpenMode, exclusive: Bool) String:
	match mode:
		Read: return "r"
		ReadWrite: return "r+"
		Write: return if exclusive: "wx" else: "w"
		WriteRead: return if exclusive: "wx+" else: "w+"
		Append: return if exclusive: "ax" else: "a"
		AppendRead: return if exclusive: "ax+" else: "a+"

/*
Opens `path` in `mode` (default `Read`). `options.exclusive` makes creation fail with EEXIST when the file exists;
`options.permissions` is applied on creation, subject to umask and OS policy.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
file := try open("out.log", OpenMode.Append)
```
*/
// ms: effect std.fs.read
// ms: effect std.fs.write
export fn open(
	path: String,
	mode: OpenMode = OpenMode.Read,
	options: OpenOptions = OpenOptions()
) FileHandle!:
	return msstd_fs_open(path, open_flags(mode, options.exclusive), options.permissions)

// Opens `path` as a directory cursor that yields one child per `read` in native order;
// close it when done. It is also a stream source:
// `stream[DirectoryEntry](try open_directory(path))`. A path that is not a directory
// returns EINVAL.
// ms: effect std.fs.read
export fn open_directory(path: String) Directory!:
	return msstd_fs_directory_open(path)

/*
Starts replacing the file at `path` with `data` (text or `Bytes`) all-or-nothing and returns its promise: readers see the old contents or the new, never a partial file.
The data goes to a new file beside `path`, is synced to stable storage, and then renamed over `path`, so `path`'s directory must be writable. When `path` is a symbolic link the file it names is replaced and the link stays; a link that cannot be resolved is replaced itself. An existing file keeps its permission bits and a new one gets 0644. On failure the temporary file is removed and `path` is unchanged.
Example: `write_atomic("config.json", text).wait()`.
*/
// ms: effect std.fs.write
export fn write_atomic(path: String, data: Writable) Promise[Unit]:
	payload := data.as_bytes()
	return owned_task[Unit](atomic_job(path.clone(), payload))

fn atomic_job(path: String, data: Bytes) fn() Unit!:
	return fn: replace_atomically(path, data)

// The file a write to `path` replaces: the target of a symbolic link, so the link
// stays, else `path`. A link that cannot be resolved (a dangling one) is replaced
// itself.
fn through_links(path: String) String:
	link := stat(path, follow_links: false)
	if link.is_error() or not link.get().is_symlink(): return path.clone()

	return canonicalize(path).get(path.clone())

// A sibling name for `path` that stays within the 255-byte file name limit: the file
// name is cut to 32 characters.
fn temporary_name(path: String, stamp: String) String:
	var split = 0
	if slash := path.last_index_of("/"): split = slash + 1
	if slash := path.last_index_of("\\"):
		if slash + 1 > split: split = slash + 1

	directory := path.slice(0, split).get("")
	name := path.drop(split)
	return "{directory}.{name.take(32)}.{stamp}.tmp"

fn replace_atomically(link: String, data: Bytes) Unit!:
	path := through_links(link)
	existing := stat(path)
	var mode = 420
	if info := existing: mode = info.permissions

	stamp := now()
	var attempt = 0

	while attempt < 16:
		temporary := temporary_name(
			path, "{stamp.unix_seconds()}.{stamp.nanoseconds()}.{attempt}"
		)
		attempt += 1

		match open(
			temporary, OpenMode.Write, OpenOptions(exclusive: true, permissions: mode)
		):
			ok(file):
				return finish_atomic(
					file, temporary, path, data, if existing.is_ok(): mode else: none
				)
			error(cause):
				if cause.kind != "EEXIST": return error(cause)

	return error(already_exists())

// Writes, syncs, closes and renames the temporary file, removing it when any step
// fails.
fn finish_atomic(
	file: FileHandle,
	temporary: String,
	path: String,
	data: Bytes,
	mode: Int?
) Unit!:
	var out = file
	var prepared = out.write(data)
	if prepared.is_ok():
		if permissions := mode: prepared = out.chmod(permissions)

	synced := if prepared.is_error(): prepared else: out.sync()
	closed := out.close()

	if synced.is_error():
		_removed := remove(temporary)
		return synced

	if closed.is_error():
		_removed := remove(temporary)
		return closed

	moved := rename(temporary, path)
	if moved.is_error():
		_cleaned := remove(temporary)
	return moved

// Moves a file or tree from `source` to `destination`, across filesystems too. It
// renames when it can. When the rename fails with a host error other than a missing or
// protected path, as a move across devices does, it copies the tree, then removes
// `source`, and removes the partial copy if copying fails. A destination that already
// exists is not replaced by the copy fallback and returns EEXIST.
// ms: effect std.fs.write
// ms: effect std.fs.delete
export fn move(source: String, destination: String) Unit!:
	renamed := rename(source, destination)
	if renamed.is_ok(): return renamed

	cause := renamed.err()
	if cause.kind == "EIO": return move_by_copy(source, destination, cause)

	return error(cause)

fn move_by_copy(source: String, destination: String, cause: Error) Unit!:
	info := stat(source, follow_links: false)
	if info.is_error(): return error(cause)
	if stat(destination, follow_links: false).is_ok(): return error(already_exists())

	copied := copy(
		source, destination, CopyOptions(recursive: info.get().is_directory())
	)

	if copied.is_error():
		_partial := remove(destination, recursive: true)
		return copied

	return remove(source, recursive: true)

/*
Watches `path` for changes and returns the changes as a stream, one event per item. Dropping the stream stops the watcher.
Without `options.interval` it uses native OS events (inotify on Linux, kqueue on macOS, ReadDirectoryChangesW on Windows).
With an interval it compares snapshots of the tree every `interval`, which must be positive, and can miss transient changes;
`max_events` and `overflow` apply only to native events and return EINVAL together with an interval.
`max_entries` bounds the paths under the root (the root, files and directories), counted when the watcher starts, and
fails with EOVERFLOW the same way on every platform.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
var watcher = try watch("src", recursive: true, options: WatchOptions(interval: 1.seconds()))
```
*/
// ms: effect std.fs.read
export fn watch(
	path: String,
	recursive: Bool = false,
	options: WatchOptions = WatchOptions()
) ReadStream[FileEvent]!:
	if interval := options.interval:
		if options.max_events.is_some() or options.overflow.is_some(): return error(
			invalid_input()
		)
		return ok(
			watch_stream(
				try msstd_fs_watch(
					path, recursive, interval, options.max_entries
				)
			)
		)

	return ok(
		watch_stream(
			try msstd_fs_watch_native(
				path, recursive, options.max_entries, options.max_events,
				options.overflow.get("error")
			)
		)
	)

// Creates a new temp directory whose contents are removed by scoped close. Prefix has
// the same validation as temporary_directory; this does not query the temp root.
// ms: effect std.fs.write
export fn temporary(prefix: String) TemporaryDirectory!:
	return msstd_fs_temporary_open(prefix)

// Returns capacity and free-space statistics for the filesystem containing `path`.
// Hosts without the query return ENOTSUP.
// ms: effect std.fs.read
export fn stat_filesystem(path: String) FileSystemInfo!:
	return msstd_fs_stat_filesystem(path)
