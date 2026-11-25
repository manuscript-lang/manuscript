// conform: tags=diagnostics
// conform: phase=check
import filesystem from "@std/os/fs.ms"

fn classify(path String) String {
	match filesystem().stat(path: path, follow_links: true) {
		error(NotFound) => return "missing"
		ok(_) => return "exists"
	}
}
// expect-error: MS2002 3:8-3:18 module does not export filesystem; @std/os/fs.ms exports: CloneMode, CopyOptions, Directory, DirectoryEntry, FileEvent, FileHandle, FileInfo, FileKind, FileSystemInfo, GlobOptions, NativeDirectory, NativeFile, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/os/fs.ms"'
// expect-error: MS2001 6:11 unknown binding filesystem; host handle getters were removed: import the operation itself, e.g. read_file from "@std/os/fs.ms", connect from "@std/net/net.ms", run from "@std/os/process.ms", now from "@std/time.ms"
