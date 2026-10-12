# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import LibraryError from "@std/errors.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"
import Timestamp from "@std/time.ms"

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
    fn canonicalize(path: String) -> Result[String, LibraryError]
    fn copy_file(source: String, destination: String, replace: Bool, max_bytes: Int) -> Result[Unit, LibraryError]
    fn create_directory(path: String, recursive: Bool) -> Result[Unit, LibraryError]
    fn create_link(path: String, target: String) -> Result[Unit, LibraryError]
    fn list(path: String, max_entries: Int) -> Result[List[DirectoryEntry], LibraryError]
    fn read_file(path: String, max_bytes: Int) -> Result[Bytes, LibraryError]
    fn read_link(path: String) -> Result[String, LibraryError]
    fn remove(path: String, recursive: Bool) -> Result[Unit, LibraryError]
    fn rename(source: String, destination: String) -> Result[Unit, LibraryError]
    fn stat(path: String, follow_links: Bool) -> Result[FileInfo, LibraryError]
    fn temporary_directory(prefix: String) -> Result[String, LibraryError]
    fn write_file(path: String, data: Bytes, replace: Bool) -> Result[Unit, LibraryError]
