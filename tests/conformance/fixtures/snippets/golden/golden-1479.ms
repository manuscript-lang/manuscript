// conform: tags=diagnostics
// conform: phase=check
import FileSystemError, filesystem from "@std/os/fs.ms"

export fn main() Int {
	fs := filesystem()
	invalid Result[Void, FileSystemError] := error(FileSystemError.InvalidInput)
	if fs.remove(path: "", recursive: true) != invalid { return 1 }
	if fs.remove(path: ".", recursive: true) != invalid { return 2 }
	if fs.remove(
		path: "child/..",
		recursive: true,
	) != invalid { return 3 }

	if base := fs.canonicalize(".") {
		if fs.remove(path: base, recursive: true) != invalid { return 4 }
	} else {
		return 8
	}

	if fs.rename(source: "", destination: "moved") != invalid { return 5 }
	if fs.rename(
		source: "sentinel",
		destination: "",
	) != invalid { return 6 }
	if fs.remove(path: "child", recursive: true).is_error() { return 7 }

	return 0
}
// expect-error: MS2002 3:8-3:23 module does not export FileSystemError; @std/os/fs.ms exports: CloneMode, CopyOptions, Directory, DirectoryEntry, FileEvent, FileHandle, FileInfo, FileKind, FileSystemInfo, GlobOptions, NativeDirectory, NativeFile, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/os/fs.ms"'
// expect-error: MS2002 3:25-3:35 module does not export filesystem; @std/os/fs.ms exports: CloneMode, CopyOptions, Directory, DirectoryEntry, FileEvent, FileHandle, FileInfo, FileKind, FileSystemInfo, GlobOptions, NativeDirectory, NativeFile, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/os/fs.ms"'
// expect-error: MS2001 6:11 unknown binding filesystem; host handle getters were removed: import the operation itself, e.g. read_file from "@std/os/fs.ms", connect from "@std/net/net.ms", run from "@std/os/process.ms", now from "@std/time.ms"
// expect-error: MS2001 7:26 unknown type FileSystemError; declare it with 'type FileSystemError:' / 'enum FileSystemError:' / 'interface FileSystemError:', declare it as a type parameter, or import it
// expect-error: MS2001 7:52 unknown binding FileSystemError; declare it with 'FileSystemError := ...' before use, define 'fn FileSystemError(...) T { ... }', or import it from a module
