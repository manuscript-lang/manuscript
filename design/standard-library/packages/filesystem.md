+++
title = "Paths and filesystem"
weight = 52
+++

# Paths and filesystem

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Path functions manipulate path text without accessing disk. FileSystem methods read or change files through a supplied service. A path string or an import alone does not grant filesystem access.

## `@std/path.ms`

```manuscript
fn basename(path: String) -> String
fn dirname(path: String) -> String
fn extension(path: String) -> String
fn is_absolute(path: String) -> Bool
fn join(parts: List[String]) -> String
fn normalize(path: String) -> String
fn relative(base: String, target: String) -> Result[String, PathError]
```

## `@std/fs.ms`

## FileSystem operations

```manuscript
fn read_file(path: String, max_bytes: Int) -> Result[Bytes, FileSystemError]
fn write_file(path: String, data: Bytes, replace: Bool) -> Result[Unit, FileSystemError]
fn stat(path: String, follow_links: Bool) -> Result[FileInfo, FileSystemError]
fn list(path: String, max_entries: Int) -> Result[List[DirectoryEntry], FileSystemError]
fn create_directory(path: String, recursive: Bool) -> Result[Unit, FileSystemError]
fn remove(path: String, recursive: Bool) -> Result[Unit, FileSystemError]
fn rename(source: String, destination: String) -> Result[Unit, FileSystemError]
fn copy_file(source: String, destination: String, replace: Bool, max_bytes: Int) -> Result[Unit, FileSystemError]
fn canonicalize(path: String) -> Result[String, FileSystemError]
fn read_link(path: String) -> Result[String, FileSystemError]
fn create_link(path: String, target: String) -> Result[Unit, FileSystemError]
fn temporary_directory(prefix: String) -> Result[String, FileSystemError]
```

## Authority and records

Process supplies `filesystem: FileSystem`. FileSystem uses a fixed startup directory for relative paths and the CLI process's native OS permissions. It is not restricted to a sandboxed subtree. The existing Files capability remains read-only.

Importing a type or constructing a path string grants no file access. Source fakes can implement the same contract. NUL paths return `InvalidInput`; filenames that cannot be represented as text return `Unsupported`. A temporary directory must be explicitly removed; dropping its path string does not remove it.

```manuscript
type FileInfo:
    name: String
    size: Int
    directory: Bool
    symlink: Bool
    modified: Timestamp

type DirectoryEntry:
    name: String
    directory: Bool
    symlink: Bool
```

## Reads, writes, and replacement

`read_file` limits cumulative bytes and closes its handle on every exit. `write_file` with `replace: false` creates exclusively; `replace: true` may truncate existing data. `copy_file` bounds input before writing and uses the same replacement rule.

Writes and copies are not transactional. An error can leave a destination prefix. Default creation permissions are 0600 for files and 0700 for directories, subject to platform behavior.

## Directories, links, and errors

Directory lists are sorted by byte-lexical order. Excess entries return `LimitExceeded`, rather than a truncated success. `stat` uses `follow_links` to choose link or target metadata.

`rename` follows the native platform's replacement and atomicity behavior, including cross-device errors. It does not fall back to copying and deleting. Recursive remove does not intentionally follow symlinks and checks cancellation between entries; it is not transactional.

Temporary-directory prefixes must be nonempty and contain no slash, backslash, or NUL. OS failures map to `NotFound`, `AlreadyExists`, `PermissionDenied`, or `Failed(message: ...)`.

## Path functions

Pure path functions use the target platform's Go filepath rules. `join` and `normalize` do not access disk. Cleaning path text does not prove that a path stays inside an authorized directory.

`relative` requires absolute paths and may return `InvalidInput` for incompatible roots. Basename, dirname, and extension follow Go filepath behavior, including treating `.profile` as an extension.

Seekable files, metadata mutation, watchers, secure subtree provisioning, and archive extraction remain future work. Existing Files and stream APIs provide bounded sequential reads.
