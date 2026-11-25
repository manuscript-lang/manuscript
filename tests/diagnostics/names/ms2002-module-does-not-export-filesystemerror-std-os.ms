// conform: tags=diagnostics
// conform: phase=check
import (
	Bytes from "@std/bytes.ms",
	FileSystemError, filesystem from "@std/os/fs.ms",
)

fn forward[T](item T) T => item
// expect-error: MS2002 5:5-5:20 module does not export FileSystemError; @std/os/fs.ms exports: CloneMode, CopyOptions, Directory, DirectoryEntry, FileEvent, FileHandle, FileInfo, FileKind, FileSystemInfo, GlobOptions, NativeDirectory, NativeFile, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/os/fs.ms"'
// expect-error: MS2002 5:22-5:32 module does not export filesystem; @std/os/fs.ms exports: CloneMode, CopyOptions, Directory, DirectoryEntry, FileEvent, FileHandle, FileInfo, FileKind, FileSystemInfo, GlobOptions, NativeDirectory, NativeFile, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/os/fs.ms"'
