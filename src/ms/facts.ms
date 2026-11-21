// The fact model of the project a source file belongs to, read by the C checker
// (`ms_tool_facts_project`, src/compiler/include/ms/tool.h): the JSON that `ms review`,
// `ms diagram` and the HTML page read. Every entity and import carries its module's
// path in the project. Run as `facts facts FILE.ms`, the form
// `ms-tooling-dev facts FILE.ms` takes, so `$MS_FACTS` can name either.
//   ms run src/ms/facts.ms --link target/c-tool/libmstool.a -- facts FILE.ms
import (
	Arg, Command, Matches from "@std/cli/command.ms",
	stderr, stdout from "@std/io/io.ms",

	run_program from "./cli.ms",
)

export enum FactsError:
	Failed(message: String)
	Unsupported(message: String)

extern fn ms_tool_facts_project(path: String) String!FactsError

fn facts_tool() Command:
	return Command(
		name: "facts.ms",
		about: "Print the fact model of a project",
		args: [
			Arg("command", help: "facts"),
			Arg("file", help: "A source file of the project"),
		],
	)

fn print_facts(m: Matches) Int!:
	if m.string("command") != "facts":
		stderr().write("usage: facts facts FILE.ms\n")?
		return ok(2)

	facts := ms_tool_facts_project(m.string("file"))

	if facts.is_error():
		match facts.err():
			Failed(message): stderr().write(f"facts: {message}\n")?
			Unsupported(message): stderr().write(f"facts: not covered: {message}\n")?

		return ok(1)

	stdout().write(facts.get())?
	return ok(0)

// ms: allow_effect std.env.read
// ms: allow_effect std.fs.read
// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn main() Int:
	return run_program(facts_tool(), print_facts)
