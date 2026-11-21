// Prints the lint findings of each file named on the command line, one per line as
// `file:line:column: [severity ]CODE: message`, and with `--fix` applies their fix edits
// until none is left. Usage:
//   ms run tools/ms/lint.ms --link libmstool.a -- [--fix] [--facts=DUMP,STDLIB] file.ms...
// `--facts` names the `ms_check_dump` program and the standard-library directory; with it the
// rules that read checker facts run too, on the nodes the C checker typed.
import (
	Arg, Command, Flag, FlagKind, Matches from "@std/cli/command.ms",
	read_file, write_file from "@std/os/fs.ms",
	quote from "@std/text.ms",

	run_program from "./cli.ms",
	load_facts from "./lint/facts.ms",
	Finding from "./lint/finding.ms",
	apply_fixes from "./lint/fixes.ms",
	lint_all from "./lint/rules.ms",
	lint_typed from "./lint/typed.ms",
)

// The most passes `--fix` makes over a file: a fix can expose another.
PASSES := 10

fn show(finding: Finding) String:
	label := if finding.severity == "error": finding.code else: f"{finding.severity} {finding.code}"
	edit := if finding.fix_from < 0: "" else: f" [fix {finding.fix_from}..{finding.fix_to} {quote(finding.fix_text)}]"
	return f"{finding.file}:{finding.line}:{finding.column}: {label}: {finding.message}{edit}"

// Applies the fixes of `path` until the text settles; whether the file changed.
fn fix_file(path: String, original: String) Bool!:
	var text = original.clone()

	for _pass in 0..PASSES:
		fixed := apply_fixes(text, lint_all(path, text))
		if fixed.applied == 0: break

		text = fixed.text.clone()

	if text == original: return ok(false)

	write_file(path, text, replace: true).wait()?
	return ok(true)

fn lint_tool() Command:
	return Command(
		name: "lint.ms",
		about: "Lint .ms files with the Manuscript rules",
		args: [Arg("files", rest: true, help: "The .ms files to lint")],
		flags: [
			Flag(
				"fix",
				FlagKind.Bool,
				help: "Apply machine-applicable fixes in place",
			),
			Flag(
				"facts",
				help: "DUMP,STDLIB: the ms_check_dump program and the stdlib directory it reads",
			),
		],
	)

fn lint_files(m: Matches) Int!:
	var status = 0
	fix := m.bool("fix")
	var dump = ""
	var stdlib = ""

	if facts := m.string_or_none("facts"):
		pair := facts.split(",")
		dump = pair[0].clone()
		stdlib = pair[1].clone()

	for path in m.list("files"):
		bytes := read_file(path).wait()

		match bytes:
			ok(data):
				text := data.decode_utf8().get_or("")
				for finding in lint_all(path, text): print(show(finding))
				if not dump.is_empty():
					if facts := load_facts(dump, stdlib, path):
						for finding in lint_typed(path, text, facts): print(
							show(finding)
						)

				if fix:
					changed := fix_file(path, text)

					if changed.is_error():
						print(f"{path}: cannot write")
						status = 1
			error(_failure):
				print(f"{path}: cannot read")
				status = 1

	return ok(status)

fn main() Int:
	return run_program(lint_tool(), lint_files)
