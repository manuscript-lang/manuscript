// Prints the canonical syntax-tree dump of each file named on the command line, in the
// format of
// `compiler/tools/ms_syntax_dump ast`: `=== path` then the dump. A file that does not parse prints
// `error line:column:offset` and nothing else.
// An argument `@list.txt` stands for the file names in that text file, one per line.
//   ms run tools/ms/syntax_dump.ms --link libmstool.a -- file.ms...
import (
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",

	dump_text from "./dump.ms",
)

// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
fn paths() List[String]:
	var out = List[String]()

	for argument in arguments():
		if list := argument.cut_prefix("@"):
			text := read_file(list).wait().get().decode_utf8().get_or("")
			for line in text.lines():
				if not line.is_empty(): out.append(line.clone())
		else: out.append(argument.clone())

	return out

fn main() Int:
	var status = 0

	for path in paths():
		print(f"=== {path}")

		match read_file(path).wait():
			ok(data): print(
				dump_text(data.decode_utf8().get_or("")).trim_end_chars(
					"\n"
				)
			)
			error(_failure):
				print(f"{path}: cannot read")
				status = 1

	return status
