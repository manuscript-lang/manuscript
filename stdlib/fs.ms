# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"
import Timestamp from "@std/time.ms"

export type FileSystemError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case NotFound
    case AlreadyExists
    case PermissionDenied
    case Unsupported
    case Failed(message: String)

export type DirectoryEntry:
    name: String
    directory: Bool
    symlink: Bool

export type FileInfo:
    name: String
    size: Int
    directory: Bool
    symlink: Bool
    modified: Timestamp

export interface FileSystem:
    fn canonicalize(path: String) -> Result[String, FileSystemError]
    fn copy_file(source: String, destination: String, replace: Bool, max_bytes: Int) -> Result[Unit, FileSystemError]
    fn create_directory(path: String, recursive: Bool) -> Result[Unit, FileSystemError]
    fn create_link(path: String, target: String) -> Result[Unit, FileSystemError]
    fn list(path: String, max_entries: Int) -> Result[List[DirectoryEntry], FileSystemError]
    fn read_file(path: String, max_bytes: Int) -> Result[Bytes, FileSystemError]
    fn read_link(path: String) -> Result[String, FileSystemError]
    fn remove(path: String, recursive: Bool) -> Result[Unit, FileSystemError]
    fn rename(source: String, destination: String) -> Result[Unit, FileSystemError]
    fn stat(path: String, follow_links: Bool) -> Result[FileInfo, FileSystemError]
    fn temporary_directory(prefix: String) -> Result[String, FileSystemError]
    fn write_file(path: String, data: Bytes, replace: Bool) -> Result[Unit, FileSystemError]

impl Error for FileSystemError:
    fn message() -> String
