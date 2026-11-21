// Prints the lint findings of each file named on the command line, one per line as
// `file:line:column: [severity ]CODE: message`, and with `--fix` applies their fix edits
// until none is left. Usage:
//   ms run tools/ms/lint.ms --link libmstool.a -- [--fix] [--json] [--deny-warnings] [--facts=DUMP,STDLIB] file.ms...
// `--facts` names the `ms_check_dump` program and the standard-library directory; with it the
// rules that read checker facts run too, on the nodes the C checker typed.
//
// A file the checker rejects is not linted: its check diagnostics are the output and
// the status is 1, as in the Rust `ms lint`. With `--json` the output is one document
// of every finding (the check document of the first file that fails instead). The
// status is 1 when a file fails its check or has an error finding, or any finding with
// `--deny-warnings`.
import (
	Bytes from "@std/bytes.ms",
	Arg, Command, Flag, FlagKind, Matches from "@std/cli/command.ms",
	stderr, stdout from "@std/io/io.ms",
	read_file, write_file from "@std/os/fs.ms",
	quote from "@std/text.ms",

	check_rows from "./check_run.ms",
	run_program from "./cli.ms",
	load_facts from "./lint/facts.ms",
	Finding from "./lint/finding.ms",
	apply_fixes from "./lint/fixes.ms",
	exit_status, findings_document from "./lint/report.ms",
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
				"json",
				FlagKind.Bool,
				help: "Emit one versioned JSON document of the findings",
			),
			Flag(
				"deny-warnings",
				FlagKind.Bool,
				help: "Fail the run on warnings, not only errors",
			),
			Flag(
				"facts",
				help: "DUMP,STDLIB: the ms_check_dump program and the stdlib directory it reads",
			),
		],
	)

// The findings of `path` on the rules that read the syntax and, with `dump`, the typed
// ones.
fn lint_file(path: String, text: String, dump: String, stdlib: String) List[Finding]:
	var found = lint_all(path, text)
	if not dump.is_empty():
		if facts := load_facts(dump, stdlib, path):
			for typed in lint_typed(path, text, facts): found.append(typed)
	return found

// What the checker printed for a file that fails it.
type Failure:
	stdout: String
	stderr: String
	// Whether `stdout` is the JSON document `--json` asked for.
	document: Bool

// The checker's report on `path` when it fails; none when the file checks or the C
// checker does not cover it. A file whose JSON document the C checker cannot give is
// still gated on its text report, which goes to standard error so that standard output
// stays JSON.
fn check_failure(path: String, json: Bool) Failure?:
	if rows := check_rows(path, json):
		if rows[2] == "0": return none
		return Failure(stdout: rows[0].clone(), stderr: rows[1].clone(), document: json)

	if not json: return none

	rows := check_rows(path, false)?
	if rows[2] == "0": return none

	return Failure(stdout: "", stderr: rows[0] + rows[1], document: false)

fn lint_files(m: Matches) Int!:
	var status = 0
	var findings = List[Finding]()
	var sources = Map[String, Bytes]()
	json := m.bool("json")
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

				// A file that does not check is reported by the checker and not linted.
				if failed := check_failure(path, json):
					stdout().write(failed.stdout).get()
					stderr().write(failed.stderr).get()
					if json and failed.document: return ok(1)

					status = 1
					continue

				found := lint_file(path, text, dump, stdlib)
				for finding in found: findings.append(finding.clone())
				sources.add(path.clone(), text.as_bytes())

				if m.bool("fix"):
					changed := fix_file(path, text)

					if changed.is_error():
						print(f"{path}: cannot write")
						status = 1
			error(_failure):
				print(f"{path}: cannot read")
				status = 1

	if json: print(findings_document(findings, sources).trim_end_chars("\n"))
	else:
		for finding in findings: print(show(finding.clone()))

	if exit_status(findings, m.bool("deny-warnings")) != 0: status = 1
	return ok(status)

fn main() Int:
	return run_program(lint_tool(), lint_files)
