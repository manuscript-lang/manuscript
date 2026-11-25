// conform: tags=diagnostics
// conform: phase=check
import (
	panic from "@std/faults.ms",
	filesystem from "@std/os/fs.ms",
)

export fn other() Int => return 4

test "source" {
	if other() != 4 { return panic("bad other") }

	if data := filesystem().read_file(path: "fixture.txt", max_bytes: 1024) {
		if data.length() != 7 { return panic("wrong fixture size") }
	} else {
		return panic("library fixture cwd changed")
	}
}
// expect-error: MS2002 4:5-4:10 unknown standard module @std/faults.ms; panic is exported by another standard module, so write: import panic from "@std/core.ms"
// expect-error: MS2002 5:5-5:15 module does not export filesystem; @std/os/fs.ms exports: CloneMode, CopyOptions, Directory, DirectoryEntry, FileEvent, FileHandle, FileInfo, FileKind, FileSystemInfo, GlobOptions, NativeDirectory, NativeFile, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/os/fs.ms"'
// expect-error: MS2001 11:30 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
// expect-error: MS2001 13:16 unknown binding filesystem; host handle getters were removed: import the operation itself, e.g. read_file from "@std/os/fs.ms", connect from "@std/net/net.ms", run from "@std/os/process.ms", now from "@std/time.ms"
// expect-error: MS2001 14:40 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
// expect-error: MS2001 16:16 unknown binding panic; add: import panic from "@std/core.ms"
// expect-fix: 1:1-1:1 "import panic from \"@std/core.ms\"\n"
