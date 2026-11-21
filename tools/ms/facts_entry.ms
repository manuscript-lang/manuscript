// `ms_tool_facts` from Manuscript: prints the fact model of one document, the JSON that
// `ms_check_dump STDLIB --facts FILE` prints, so `make c-tools-test` compares the two.
//   ms run tools/ms/facts_entry.ms --link target/c-tool/libmstool.a -- FILE.ms
// With `--project` it prints the facts of the project FILE belongs to (`ms_tool_facts_project`):
//   ms run tools/ms/facts_entry.ms --link target/c-tool/libmstool.a -- --project FILE.ms
import (
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
)

export enum FactsError:
	Failed(message: String)
	Unsupported(message: String)

extern fn ms_tool_facts(text: String) String!FactsError

extern fn ms_tool_facts_project(path: String) String!FactsError

// ms: allow_effect std.fs.read
// ms: allow_effect std.env.read
// ms: allow_effect std.console.write
fn main() Int:
	args := arguments()

	if args.length() == 2 and args[0] == "--project":
		project := ms_tool_facts_project(args[1].clone())
		if project.is_error(): return 1

		var project_out = stdout()
		if project_out.write(project.get()).is_error(): return 1
		return 0

	if args.length() != 1: return 2

	data := read_file(args[0]).wait()
	if data.is_error(): return 2

	source := data.get().decode_utf8()
	if source.is_none(): return 2

	facts := ms_tool_facts(source.get())
	if facts.is_error(): return 1

	var out = stdout()
	written := out.write(facts.get())
	if written.is_error(): return 1

	return 0
