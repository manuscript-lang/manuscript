// Prints the canonical syntax-tree dump of each file named on the command line, in the
// format of
// `src/compiler/tools/ms_syntax_dump ast`: `=== path` then the dump. A file that does not parse prints
// `error line:column:offset` and nothing else.
// An argument `@list.txt` stands for the file names in that text file, one per line.
//   ms run src/ms/syntax_dump.ms --link libmstool.a -- file.ms...
import (
	Arg, Command, Matches from "@std/cli/command.ms",
	read_file from "@std/os/fs.ms",

	run_program from "./cli.ms",
	dump_text from "./dump.ms",
)

// ms: allow_effect std.fs.read
fn paths(given: List[String]) List[String]:
	var out = List[String]()

	for argument in given:
		if list := argument.cut_prefix("@"):
			text := read_file(list).wait().get().decode_utf8().get_or("")
			for line in text.lines():
				if not line.is_empty(): out.append(line.clone())
		else: out.append(argument.clone())

	return out

fn syntax_dump_tool() Command:
	return Command(
		name: "syntax_dump.ms",
		about: "Print the syntax tree of each file",
		args: [
			Arg(
				"files",
				rest: true,
				help: "Files; @LIST names a file that lists them",
			)
		],
	)

fn dump_files(m: Matches) Int!:
	var status = 0

	for path in paths(m.list("files")):
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

	return ok(status)

fn main() Int:
	return run_program(syntax_dump_tool(), dump_files)
