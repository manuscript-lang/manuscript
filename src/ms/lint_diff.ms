// Compares the Manuscript lexical lint with the Rust `ms lint` on mutated copies of
// Manuscript files. Each file is copied under WORKDIR with trailing spaces, `// 2`
// comments and a dropped final newline added at seeded places; both linters read the
// copy and their findings must be equal. Files the Rust checker rejects are skipped (it
// lints only programs that check).
//
//   ms run src/ms/lint_diff.ms --link libmstool.a -- RUST_MS WORKDIR SEED file.ms...
import (
	Arg, Command, FlagKind, Matches from "@std/cli/command.ms",
	parse from "@std/data/json.ms",
	create_directory, read_file, write_file from "@std/os/fs.ms",
	run from "@std/os/process.ms",

	run_program from "./cli.ms",
	lint_source from "./lint/text.ms",
)

type Place:
	line: Int
	column: Int

type Entry:
	code: String
	message: String
	position: Place
	severity: String = ""
	phase: String? = none

type Report:
	diagnostics: List[Entry]

fn directory_of(path: String) String:
	if slash := path.last_index_of("/"): return path.slice(0, slash)
	return "."

fn ends_like_expression(line: String) Bool:
	if line.contains("\""): return false

	bytes := line.as_bytes()
	if bytes.length() == 0: return false

	last := bytes[bytes.length() - 1]
	return (
		(last >= 48 and last <= 57)
		or (last >= 65 and last <= 90)
		or (last >= 97 and last <= 122)
		or last == 95
		or last == 41
		or last == 93
	)

// The mutated copy of `text`: seeded, so a failure reruns exactly.
fn mutate(text: String, seed: Int, strip_final_newline: Bool) String:
	var out = ""
	var number = 0

	for line in text.split_after("\n"):
		number += 1

		body := line.cut_suffix("\n").get_or(line)
		ending := if line.ends_with("\n"): "\n" else: ""
		roll := (number * 7919 + seed * 104729) % 100

		if roll < 7: out = out.concat(f"{body}  {ending}")
		else if roll < 10 and ends_like_expression(body): out = out.concat(
			f"{body} // 2{ending}"
		)
		else: out = out.concat(line)

	if strip_final_newline: return out.trim_end_chars("\n")

	return out

fn show(code: String, severity: String, line: Int, column: Int, message: String) String:
	return f"{line}:{column} {code} {severity} {message}"

fn ours(path: String, text: String) List[String]:
	var lines = List[String]()
	for finding in lint_source(path, text):
		lines.append(
			show(
				finding.code,
				finding.severity,
				finding.line,
				finding.column,
				finding.message,
			)
		)
	lines.sort()
	return lines

// Rust findings for the lexical codes, or none when the program does not check.
// ms: allow_effect std.process.run
fn theirs(rust: String, path: String) List[String]?!:
	output := run(rust, ["lint", "--json", path]).wait()?
	report := parse[Report](output.stdout.decode_utf8().get_or(""))?
	for entry in report.diagnostics:
		if entry.phase.is_some(): return ok(none)

	var lines = List[String]()
	for entry in report.diagnostics:
		if entry.code == "MSL001" or entry.code == "MSL002" or entry.code == "MSL133":
			lines.append(
				show(
					entry.code,
					entry.severity,
					entry.position.line,
					entry.position.column,
					entry.message,
				)
			)
	lines.sort()
	return ok(lines.distinct())

fn lint_diff_tool() Command:
	return Command(
		name: "lint_diff.ms",
		about: "Compare the lint findings of the Rust ms and this linter on mutated copies",
		args: [
			Arg("rust", help: "The Rust ms to ask"),
			Arg("work", help: "Where the mutated copies go"),
			Arg("seed", kind: FlagKind.Int, help: "The mutation seed"),
			Arg(
				"files",
				rest: true,
				help: "The .ms files to mutate and lint",
			),
		],
	)

fn compare(m: Matches) Int!:
	rust := m.string("rust")
	work := m.string("work")
	seed := m.int("seed")
	var checked = 0
	var findings = 0
	var failed = 0

	for index in 3..(3 + m.list("files").length()):
		source := m.list("files")[index - 3].clone()
		data := read_file(source).wait().get().decode_utf8().get_or("")
		copy := f"{work}/{source}"
		void create_directory(directory_of(copy), recursive: true)
		void write_file(copy, mutate(data, seed + index, index % 5 == 0).to_bytes()).wait()

		if expected := theirs(rust, copy.clone()).get():
			actual := ours(copy, read_file(copy).wait().get().decode_utf8().get_or(""))
			checked += 1
			findings += actual.length()

			if actual != expected:
				failed += 1
				print(f"DIFFERENT {source}")
				print(f"  rust: {expected}")
				print(f"  ours: {actual}")

	print(f"{checked} files, {findings} findings, {failed} different")
	if failed > 0: return ok(1)

	return ok(0)

fn main() Int:
	return run_program(lint_diff_tool(), compare)
