// `ms_tool_facts` from Manuscript: prints the fact model of one document, the JSON that
// `ms_check_dump STDLIB --facts FILE` prints, so `make c-tools-test` compares the two.
//   ms run src/ms/facts_entry.ms --link target/c-tool/libmstool.a -- FILE.ms
// With `--project` it prints the facts of the project FILE belongs to
// (`ms_tool_facts_project`):
//   ms run src/ms/facts_entry.ms --link target/c-tool/libmstool.a -- --project FILE.ms
import (
	Arg, Command, Flag, FlagKind, Matches from "@std/cli/command.ms",
	stdout from "@std/io/io.ms",
	read_file from "@std/os/fs.ms",

	run_program from "./cli.ms",
)

export enum FactsError:
	Failed(message: String)
	Unsupported(message: String)

extern fn ms_tool_facts(text: String) String!FactsError

extern fn ms_tool_facts_project(path: String) String!FactsError

fn facts_tool() Command:
	return Command(
		name: "facts_entry.ms",
		about: "Print the fact model of a document or, with --project, of its project",
		flags: [
			Flag(
				"project",
				FlagKind.Bool,
				help: "Print the facts of the project FILE belongs to",
			)
		],
		args: [Arg("file", help: "A source file")],
	)

fn print_facts(m: Matches) Int!:
	file := m.string("file")

	if m.bool("project"):
		project := ms_tool_facts_project(file)
		if project.is_error(): return ok(1)

		stdout().write(project.get())?
		return ok(0)

	data := read_file(file).wait()
	if data.is_error(): return ok(2)

	source := data.get().decode_utf8()
	if source.is_none(): return ok(2)

	facts := ms_tool_facts(source.get())
	if facts.is_error(): return ok(1)

	stdout().write(facts.get())?
	return ok(0)

// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Int:
	return run_program(facts_tool(), print_facts)
