// conform: tags=closures,formatter,modules,parser,stdlib-bytes,stdlib-fs,strings,tier-io,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=documentation/core-language/functions/function-values-and-closures.md:83
import (
	Bytes from "@std/bytes.ms",
	open from "@std/os/fs.ms",
)

fn notes_reader(path: String) fn() Result[Bytes, Error]:
	return fn:
		file := open(path: path)?
		return file.read_file(max_bytes: 1048576)
