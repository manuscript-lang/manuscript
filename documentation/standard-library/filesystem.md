+++
title = "Files and paths"
weight = 10
+++

# Files and paths

Path functions manipulate path text without accessing disk. FileSystem methods read or change files through a supplied service. A path string or an import alone does not grant filesystem access.

See the [filesystem reference](reference/fs.md) and [path reference](reference/path.md) for types, methods, and import paths.

## Files and directories

Import `filesystem()` from `@std/fs.ms` to obtain the filesystem service. Acquire handles inside `with`. This fragment belongs in a function returning `Result[Unit, FileSystemError]`:

```manuscript
with file = try filesystem().open(path: path, flags: "r+", mode: 384):
    let written = try file.write_at(offset: 0, data: "HELLO".to_bytes())
    let bytes = try file.read_at(offset: 0, max_bytes: 5)
    let synced = try file.sync()
```

`384` is decimal for Unix permission bits `0600`. Opening accepts `r`, `r+`, `w`, `wx`, `w+`, `wx+`, `a`, `ax`, `a+`, and `ax+`. `x` makes creation exclusive. Permission arguments accept `0..4095` (`07777`), including setuid, setgid, and sticky bits where the native OS supports them. `open_flags` accepts numeric native flags from `fs.constants()`; these numbers are host-specific. Paths use the native filesystem dialect, reject NUL, and use host OS permissions. Relative paths on CLI roots use the live working directory; embedded capabilities constructed with a directory retain that base. Importing the FileSystem type alone does not obtain a service.

## File reads and writes

`read_file` limits cumulative bytes and closes its handle on every exit. `write_file` with `replace: false` creates exclusively; `replace: true` may truncate existing data. Default creation permissions are 0600 for files and 0700 for directories, subject to platform behavior. Writes and copies can leave a partial destination after an error.

`FileHandle` supports sequential `read`/`write`, positional `read_at`/`write_at`, bounded `read_file`, `write_file`, `append_file`, `read_vectors`/`write_vectors`, `read_lines`, `seek`, `stat`, `truncate`, `chmod`, `chown`, `set_times`, `sync`, `data_sync`, and idempotent `close`. A chunk read returns up to 64 KiB; sequential EOF is `none`, positional EOF is empty `Bytes`. `read_vectors` accepts each size up to 64 KiB and a combined size up to 16 MiB. Vector offset `-1` uses the current position. Seek origins are `0` (start), `1` (current), and `2` (end). `read_file`, `write_file`, and `read_lines` start at the current position. Line reads validate UTF-8, remove line terminators, and enforce both byte and line limits.

## Streams and close

`reader()` and `writer()` adapt the same handle to the existing stream contracts, translating `FileSystemError` into `IoError`. Closing an adapter closes the handle and every alias. `flush` synchronizes the file; this is stronger than flushing a userspace buffer. Operations serialize shared file positions. Close prevents new calls, interrupts pollable I/O, and joins admitted calls. Parent cancellation unwinds; it is not EOF. Acquisition releases a resource when cancellation wins before delivery. Regular-file OS calls can delay cancellation until they return.

## Directories and metadata

Directory lists are sorted. Excess entries return `LimitExceeded`, rather than a truncated success. `stat` uses `follow_links` to select link or target metadata. `rename` uses native replacement and atomicity rules and does not fall back to copying across devices. Recursive removal does not intentionally follow symlinks and checks cancellation between entries.

Temporary-directory prefixes must be nonempty and contain no slash, backslash, or NUL. `temporary_directory` returns a path that the caller must remove; `temporary` returns a scoped resource that removes its directory on close.

Directory cursors expose their native `path()` and return one `DirectoryEntry` or `none` and require close. `FileInfo.mode` contains POSIX type and permission bits; `permissions` contains only permission/special bits. The record supplies size, modified/accessed/changed times, optional `created` birth time, block size/allocation, device/inode/link count, owner IDs, and regular/symlink/directory/FIFO/socket/device classifications. `exact` contains arbitrary-precision numeric metadata and nanosecond timestamps. Native fields absent on a host are zero; unavailable birth time is `none`. Accessed/changed times fall back to modified time when unavailable, including the current Windows adapter. Linux does not support no-follow chmod; macOS supports no-follow chmod and timestamps. Windows supports descriptor timestamps, while no-follow metadata updates return `Unsupported`. Windows permission bits express native read/write policy.

## Copying trees

`copy` accepts `CopyOptions`: recursive traversal, replacement, error-on-existing, dereferencing, timestamp preservation, verbatim symlinks, clone policy (`none`, `try`, or `force`), and shared entry/byte budgets. An optional filter runs sequentially for each source/destination pair and can prune directories. Without dereferencing, links are copied as links; relative targets are resolved against the source unless verbatim copying is requested. Dereferencing detects ancestor cycles. Copy rejects copying a tree into itself and traversing a destination symlink as a directory. Existing directories merge; collisions skip, fail, or replace according to the options. Native cloning uses Linux reflinks or macOS clonefile; `try` falls back to byte copying and `force` reports an OS error when unavailable. Windows has no clone adapter. The root and descendants share `max_entries`; all copied data shares `max_bytes`. Copying and writing can leave a partial prefix after an error.

## Watching files

`watch_native` retains OS events while the caller is busy. It bounds directory watches with `max_entries` and buffered events with `max_events`; overflow policy `error` returns `LimitExceeded`, while `ignore` drops excess events. Recursive watches admit newly created directories and do not follow directory symlinks. Events use `rename` for creation/removal/rename and `change` for writes/metadata changes. OS backends can coalesce events, report a containing directory, or overflow; event names and granularity are platform-dependent. Close stops the backend and joins its worker and admitted waiter. Cancellation during acquisition releases the backend.

Polling `watch` compares bounded snapshots after each requested interval. They report sorted `FileEvent` records with `rename` for appearance/disappearance and `change` for changed metadata. A vanished root reports disappearance. Recursive watches do not follow symlinks. Polling can coalesce or miss transient changes between snapshots; this is not a native OS event stream. Close and parent cancellation interrupt a waiting `next` without leaving a worker running.

## Path functions

Import pure path functions from `@std/path.ms`, or use `posix()`/`win32()` for a dialect independent of the host. No path operation reads cwd or touches files. `join` and `normalize` only clean path text; this does not prove that a path stays inside an authorized directory. `relative` requires absolute paths; paths on different Windows roots produce the absolute target. A leading dot alone does not form an extension: `extension(".profile")` returns an empty string, while `extension("notes.txt")` returns `".txt"`.

Windows parsing preserves the spelling of separators. Normalization emits backslashes. UNC and drive roots remain distinct; relative comparisons are case-insensitive for Windows. Drive-relative components use an earlier explicit absolute base on the chosen drive; an unknown drive base returns `InvalidInput`, since resolving it would require ambient per-drive cwd. Later absolute components supersede earlier paths. Relative identical paths produce an empty string. `PathParts.directory` and `base` take precedence over `root`, `name`, and `extension` when formatting.

## Glob patterns

Globs support segment wildcards, character classes, `**`, brace alternatives, numeric brace ranges, and `@`, `+`, `?`, `*`, `!` extended groups. Hidden segments require an explicit leading dot. Patterns are limited to 4096 bytes; numeric ranges have at most 1025 entries and endpoints within `-100000..100000`. Use `/` between filesystem glob segments on every host. Brace alternatives can cross directory separators; alphabetic and padded numeric ranges are supported. Basic filesystem `glob` returns sorted relative paths without following directory symlinks; its `max_entries` bounds matched output. `glob_entries` accepts multiple patterns, pattern/callback exclusions that prune traversal, optional link following with cycle prevention, and separate visited-entry/result limits. Results are sorted, deduplicated `PathEntry` records. Absolute and parent-relative patterns can visit outside the supplied base, within the authority granted by the filesystem capability.
