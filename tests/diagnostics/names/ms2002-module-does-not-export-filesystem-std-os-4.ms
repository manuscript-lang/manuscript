// conform: tags=diagnostics
// conform: phase=check
import (
	filesystem from "@std/os/fs.ms",
	expect_true, fail from "@std/test/test.ms",
)

test "fixture next to the manifest" {
	match filesystem().read_file(path: "golden/input.txt", max_bytes: 1024) {
		ok(data) => {
			if data.length() != 7 {
				return fail("wrong fixture size")
			}
		}
		error(_) => {
			return fail("fixture not found")
		}
	}
}
// expect-error: MS2002 4:5-4:15 module does not export filesystem; @std/os/fs.ms exports: CloneMode, CopyOptions, Directory, DirectoryEntry, FileEvent, FileHandle, FileInfo, FileKind, FileSystemInfo, GlobOptions, NativeDirectory, NativeFile, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/os/fs.ms"'
// expect-error: MS2001 9:11 unknown binding filesystem; host handle getters were removed: import the operation itself, e.g. read_file from "@std/os/fs.ms", connect from "@std/net/net.ms", run from "@std/os/process.ms", now from "@std/time.ms"
