+++
title = "Paths and filesystem"
weight = 52
+++

# Paths and filesystem

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

## `@std/path.ms`

```text
fn basename(path: String) -> String
fn dirname(path: String) -> String
fn extension(path: String) -> String
fn is_absolute(path: String) -> Bool
fn join(parts: List[String]) -> String
fn normalize(path: String) -> String
fn relative(base: String, target: String) -> Result[String, LibraryError]
```

## `@std/fs.ms`

## FileSystem operations

```text
fn read_file(path: String, max_bytes: Int) -> Result[Bytes, LibraryError]
fn write_file(path: String, data: Bytes, replace: Bool) -> Result[Unit, LibraryError]
fn stat(path: String, follow_links: Bool) -> Result[FileInfo, LibraryError]
fn list(path: String, max_entries: Int) -> Result[List[DirectoryEntry], LibraryError]
fn create_directory(path: String, recursive: Bool) -> Result[Unit, LibraryError]
fn remove(path: String, recursive: Bool) -> Result[Unit, LibraryError]
fn rename(source: String, destination: String) -> Result[Unit, LibraryError]
fn copy_file(source: String, destination: String, replace: Bool, max_bytes: Int) -> Result[Unit, LibraryError]
fn canonicalize(path: String) -> Result[String, LibraryError]
fn read_link(path: String) -> Result[String, LibraryError]
fn create_link(path: String, target: String) -> Result[Unit, LibraryError]
fn temporary_directory(prefix: String) -> Result[String, LibraryError]
```

## Authority and records

CLI Process adds `filesystem: FileSystem & Shareable`. The existing Files capability remains read-only. FileSystem is host-created, uses a fixed startup directory for relative paths, and grants the CLI's native OS file authority; this distribution does not claim a sandboxed subtree capability. Imports and path Strings grant no authority. Source fakes implement the contract normally. NUL paths return InvalidInput; unrepresentable filename text returns Unsupported. Acquired temporary directories require explicit removal, not merely dropping a String.

```text
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

Read_file bounds cumulative bytes and closes its handle on every exit. Write_file with replace false creates exclusively; true may truncate existing data. Copy_file bounds input before writing and uses the same replacement contract. Writes/copies are not transactional, and failures may leave a destination prefix. Creation defaults are 0600 files and 0700 directories, subject to platform behavior. Rename follows native replacement/atomicity behavior, including target differences and cross-device errors; there is no implicit copy/delete fallback. Recursive remove does not intentionally follow symlinks and checks cancellation between entries; it is not transactional. Directory lists are byte-lexically sorted and return LimitExceeded rather than a truncated success. Stat's follow_links determines link-versus-target metadata. Temporary prefix must be nonempty and exclude slash, backslash and NUL. OS errors map to NotFound, AlreadyExists, PermissionDenied or Failed(message).

Pure path functions use the native target's filepath rules. Join/normalize do not access disk; lexical cleanup never proves containment. Relative requires absolute paths and may return InvalidInput for incompatible roots. Basename/dirname/extension follow Go filepath behavior, including `.profile` as an extension. Seekable files, metadata mutation, watchers, secure subtree provisioning, and archive extraction remain deferred; existing Files/stream APIs provide bounded sequential reads.
