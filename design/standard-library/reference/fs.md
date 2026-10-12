+++
title = "fs"
+++

# @std/fs.ms

Import each required symbol with `import Name from "@std/fs.ms"`.

## DirectoryEntry

Kind: record.

```text
DirectoryEntry: DirectoryEntry
field name: String
field directory: Bool
field symlink: Bool
```

## FileInfo

Kind: record.

```text
FileInfo: FileInfo
field name: String
field size: Int
field directory: Bool
field symlink: Bool
field modified: Timestamp
```

## FileSystem

Kind: interface.

```text
FileSystem: FileSystem
operation canonicalize: fn(path: String)->Result[String, FileSystemError]
operation copy_file: fn(source: String, destination: String, replace: Bool, max_bytes: Int)->Result[Unit, FileSystemError]
operation create_directory: fn(path: String, recursive: Bool)->Result[Unit, FileSystemError]
operation create_link: fn(path: String, target: String)->Result[Unit, FileSystemError]
operation list: fn(path: String, max_entries: Int)->Result[List[DirectoryEntry], FileSystemError]
operation read_file: fn(path: String, max_bytes: Int)->Result[Bytes, FileSystemError]
operation read_link: fn(path: String)->Result[String, FileSystemError]
operation remove: fn(path: String, recursive: Bool)->Result[Unit, FileSystemError]
operation rename: fn(source: String, destination: String)->Result[Unit, FileSystemError]
operation stat: fn(path: String, follow_links: Bool)->Result[FileInfo, FileSystemError]
operation temporary_directory: fn(prefix: String)->Result[String, FileSystemError]
operation write_file: fn(path: String, data: Bytes, replace: Bool)->Result[Unit, FileSystemError]
```

## FileSystemError

Kind: alternative.

```text
FileSystemError: FileSystemError
implements: Error
case InvalidInput
case InvalidData
case LimitExceeded
case NotFound
case AlreadyExists
case PermissionDenied
case Unsupported
case Failed(message: String)
operation message: fn()->String
```

