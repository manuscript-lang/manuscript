// conform: tags=closures,diagnostics,modules,stdlib-bytes,stdlib-fs,strings,tier-io,try-result,scope-cleanup
// conform: phase=check
// conform: origin=documentation/core-language/functions/function-values-and-closures.md:83
import (
	Bytes from "@std/bytes.ms",
	OpenMode, open from "@std/os/fs.ms",
)

fn notes_reader(path: String) fn() Result[Bytes, Error]:
	return fn:
		file := open(path, OpenMode.Read)?
		return file.read_file(max_bytes: 1048576)
