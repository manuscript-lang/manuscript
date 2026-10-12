+++
title = "fs"
+++

# @std/fs.ms

Import each required symbol with `import Name from "@std/fs.ms"`.

## DirectoryEntry

Kind: record.

```manuscript
DirectoryEntry: DirectoryEntry
field name: String
field directory: Bool
field symlink: Bool
```

## FileInfo

Kind: record.

```manuscript
FileInfo: FileInfo
field name: String
field size: Int
field directory: Bool
field symlink: Bool
field modified: Timestamp
```

## FileSystem

Kind: interface.

```manuscript
FileSystem: FileSystem
operation canonicalize: fn(path: String)->Result[String, LibraryError]
operation copy_file: fn(source: String, destination: String, replace: Bool, max_bytes: Int)->Result[Unit, LibraryError]
operation create_directory: fn(path: String, recursive: Bool)->Result[Unit, LibraryError]
operation create_link: fn(path: String, target: String)->Result[Unit, LibraryError]
operation list: fn(path: String, max_entries: Int)->Result[List[DirectoryEntry], LibraryError]
operation read_file: fn(path: String, max_bytes: Int)->Result[Bytes, LibraryError]
operation read_link: fn(path: String)->Result[String, LibraryError]
operation remove: fn(path: String, recursive: Bool)->Result[Unit, LibraryError]
operation rename: fn(source: String, destination: String)->Result[Unit, LibraryError]
operation stat: fn(path: String, follow_links: Bool)->Result[FileInfo, LibraryError]
operation temporary_directory: fn(prefix: String)->Result[String, LibraryError]
operation write_file: fn(path: String, data: Bytes, replace: Bool)->Result[Unit, LibraryError]
```

