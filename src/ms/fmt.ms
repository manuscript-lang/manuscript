// `ms fmt [--check] [--json] [--] <file.ms>...`: formats the files in place, or reports the ones
// that need it. The formatter is libms's (`ms_tool_format`,
// src/compiler/include/ms/tool.h), so a program that imports this module links
// `libmstool.a`. A directory or an `ms.toml` is expanded by `ms_tool_discover`. A
// workspace, `--drop-labels` (the label rewrite), a file that is missing or not valid
// UTF-8, and every error go to the Rust command, so those keep the Rust wording.
import (
	Bytes from "@std/bytes.ms",
	Matches from "@std/cli/command.ms",
	JsonValue from "@std/data/json.ms",
	working_directory from "@std/os/env.ms",
	canonicalize,
	chmod,
	read_file,
	remove,
	rename,
	stat,
	write_file from "@std/os/fs.ms",
	relative, resolve from "@std/os/path.ms",
	expect_equal from "@std/test/test.ms",

	flag, list_of, number, object, render_document, text, with from "./json_out.ms",
	root_members from "./workspace.ms",
)

// The first syntax error: `code` is the byte offset, `message` is
// "<code>\t<line>\t<column>\t<text>".
export enum FormatError:
	Failed(code: Int, message: String)

extern fn ms_tool_format(text: String) String!FormatError

// The files of a directory or of the project an ms.toml names. Status 1 is an error
// with the Rust text and status 2 a project the C reader does not cover; both leave the
// command to the Rust `ms`, which words them.
export enum DiscoverError:
	Failed(message: String)
	Unsupported(message: String)

extern fn ms_tool_discover(target: String) List[String]!DiscoverError

// What expanding the targets came to: the files to format and the targets that failed,
// each as the outcome it reports.
type Expanded:
	files: List[String] = []
	failures: List[Outcome] = []
	// A project libms does not cover: the Rust command answers.
	rust: Bool = false

// The failure of `target` as `ms fmt` reports it. A manifest error carries its
// position, as
// `file:line:column: cause`; every other message is plain.
fn failure_of(cwd: String, target: String, message: String) Outcome:
	display := shown_target(cwd, target)

	// A path that is not there reads as the missing file it is.
	if (
		message.starts_with("stat ")
		and message.ends_with(": no such file or directory")
	): return missing(display)

	parts := message.split(": ")

	if parts.length() >= 2:
		place := parts[0].split(":")

		if place.length() >= 3:
			line := place[place.length() - 2].parse_int()
			column := place[place.length() - 1].parse_int()

			if line.is_some() and column.is_some():
				cause := parts.drop(1).join(": ")
				offset := offset_of(target, line.get(), column.get())
				return Outcome(
					display.clone(),
					target.clone(),
					"",
					Issue(
						"MS2001",
						"resolution",
						cause.clone(),
						line.get(),
						column.get(),
						offset,
					),
					f"{display}:{line.get()}:{column.get()}: {cause}",
				)

	return Outcome(
		display.clone(),
		target.clone(),
		"",
		Issue("MSF002", "format", message.clone(), 1, 1, 0),
		message.clone(),
	)

fn missing(display: String) Outcome:
	message := f"file not found: {display}; check the path and run from the directory that contains it"
	return Outcome(
		display.clone(),
		display.clone(),
		"",
		Issue("MSF002", "format", message.clone(), 1, 1, 0),
		message.clone(),
	)

// The byte offset of `line` and `column` (both from 1) in the file at `path`.
fn offset_of(path: String, line: Int, column: Int) Int:
	data := read_file(path).wait()
	if data.is_error(): return 0

	text := data.get().decode_utf8().get_or("")
	var at = 0
	var current = 1

	for part in text.split("\n"):
		if current == line: return at + column - 1

		at += part.length() + 1
		current += 1

	return 0

fn shown_target(cwd: String, target: String) String:
	absolute := resolve(cwd, [target.clone()])
	if absolute.is_error(): return target.clone()

	return display_of(cwd, absolute.get())

// The files `ms fmt` formats for each target: a file is itself, a directory or an
// `ms.toml` is what libms finds there.
fn expand_targets(cwd: String, targets: List[String]) Expanded:
	var out = Expanded()

	for target in targets:
		// A workspace root without a `[project]` stands for its members, as in the
		// other commands.
		var manifests = [target.clone()]

		if members := root_members(target):
			manifests = []
			for member in members: manifests.append(member.manifest.clone())

		for manifest in manifests:
			found := ms_tool_discover(manifest)

			if found.is_error():
				match found.err():
					Failed(message): out.failures.append(
						failure_of(
							cwd,
							manifest,
							message.clone(),
						)
					)
					Unsupported(_): out.rust = true

				continue

			for path in found.get(): out.files.append(path.clone())

	return out

// One file's result in the `--json` document.
type Outcome:
	display: String
	path: String
	// clean, formatted, needs_formatting or error.
	state: String
	// The diagnostic of an error or of drift: none for a file that is fine.
	issue: Issue? = none
	// What the terminal gets on standard error.
	message: String = ""

type Issue:
	code: String
	phase: String
	message: String
	line: Int
	column: Int
	offset: Int

export type Request:
	check: Bool = false
	json: Bool = false
	targets: List[String] = []
	// The usage error to print with status 2, when there is one.
	usage: String = ""
	// Whether the Rust command must answer.
	rust: Bool = false

// The options and targets the command tree parsed for `ms fmt`.
export fn parse_request(m: Matches) Request:
	var request = Request(
		check: m.bool("check"),
		json: m.bool("json"),
		targets: m.list("targets"),
	)

	if m.bool("drop-labels"):
		request.rust = true
	else if request.targets.contains(""):
		request.usage = "ms fmt: an input argument is empty; pass a .ms file, directory, or ms.toml"
	else if request.json and not request.check:
		request.usage = "--json requires ms fmt --check; remove --json to format files in place"

	return request

// How `path` reads on the terminal: relative to `cwd` inside it, absolute outside.
export fn display_of(cwd: String, absolute: String) String:
	shown := relative(cwd, absolute)
	if shown.is_error(): return absolute.clone()

	var shortest = shown.get().clone()
	if shortest == ".." or shortest.starts_with("../") or shortest.starts_with("..\\"): return absolute.clone()

	if shortest.starts_with("-"): shortest = "./" + shortest
	return shortest

fn describe(display: String, details: String, offset: Int) Issue:
	parts := details.split("\t")
	if parts.length() < 4: return Issue(
		"MS1000",
		"parse",
		details.clone(),
		1,
		1,
		offset,
	)

	message := parts.drop(3).join("\t")
	return Issue(
		parts[0].clone(),
		"parse",
		message,
		parts[1].parse_int().get_or(1),
		parts[2].parse_int().get_or(1),
		offset,
	)

// Replaces `path` with `formatted`, keeping its permissions, through a file beside it.
fn write_formatted(path: String, formatted: String, mode: Int, unique: Int) Void!:
	temp := f"{path}.manuscript-format-{unique}"
	write_file(temp, formatted, replace: true).wait()?
	chmod(temp, mode)?
	rename(temp, path)?
	return ok()

fn check_one(
	display: String,
	path: String,
	source: String,
	request: Request,
	mode: Int,
	unique: Int,
) Outcome:
	formatted := ms_tool_format(source)

	if formatted.is_error():
		match formatted.err():
			Failed(offset, details):
				issue := describe(display, details, offset)
				return Outcome(
					display.clone(),
					path.clone(),
					"error",
					issue.clone(),
					f"{display}:{issue.line}:{issue.column}: {issue.phase}: {issue.message}\nfmt only formats source that parses; fix the syntax error above, then re-run ms fmt {display}",
				)

	if source == formatted.get(): return Outcome(display.clone(), path.clone(), "clean")

	if request.check:
		message := f"Formatting needed: {display}; run ms fmt {display} to rewrite it"
		return Outcome(
			display.clone(),
			path.clone(),
			"needs_formatting",
			Issue("MSF001", "format", message.clone(), 1, 1, 0),
			message.clone(),
		)

	written := write_formatted(path, formatted.get(), mode, unique)

	if written.is_error():
		message := f"cannot rewrite {display}: {written.err().message}"
		return Outcome(
			display.clone(),
			path.clone(),
			"error",
			Issue("MSF002", "format", message.clone(), 1, 1, 0),
			message.clone(),
		)

	return Outcome(display.clone(), path.clone(), "formatted")

fn issue_json(display: String, issue: Issue) JsonValue:
	var position = object()
	position = with(position, "file", text(display))
	position = with(position, "line", number(issue.line))
	position = with(position, "column", number(issue.column))
	position = with(position, "offset", number(issue.offset))

	var out = object()
	out = with(out, "code", text(issue.code))
	out = with(out, "phase", text(issue.phase))
	out = with(out, "message", text(issue.message))
	return with(out, "position", position)

// Whether diagnostic `a` sorts before `b`: by file, line, column, code, then message.
fn before(a: Outcome, b: Outcome) Bool:
	left := a.issue.get_or(Issue("", "", "", 0, 0, 0))
	right := b.issue.get_or(Issue("", "", "", 0, 0, 0))
	if a.display != b.display: return a.display < b.display
	if left.line != right.line: return left.line < right.line
	if left.column != right.column: return left.column < right.column
	if left.code != right.code: return left.code < right.code

	return left.message < right.message

fn document(outcomes: List[Outcome]) String:
	var files = List[JsonValue]()
	var issues = List[Outcome]()

	for outcome in outcomes:
		if not outcome.state.is_empty():
			var item = object()
			item = with(item, "path", text(outcome.display))
			item = with(item, "status", text(outcome.state))
			files.append(item)

		if outcome.issue.is_some(): issues.append(outcome.clone())

	var sorted = List[Outcome]()

	for outcome in issues:
		var at = sorted.length()
		while at > 0 and before(outcome, sorted[at - 1]): at -= 1
		sorted.insert(at, outcome.clone())

	var diagnostics = List[JsonValue]()
	for outcome in sorted:
		if issue := outcome.issue: diagnostics.append(
			issue_json(outcome.display, issue)
		)

	var out = object()
	out = with(out, "format", number(1))
	out = with(out, "files", list_of(files))
	out = with(out, "diagnostics", list_of(diagnostics))
	return render_document(out)

// What `ms fmt` printed and how it ended.
export type Printed:
	stdout: String = ""
	stderr: String = ""
	status: Int = 0

// Runs `ms fmt`; none when the Rust command must, before any file is touched.
export fn run_fmt(m: Matches) Printed?:
	request := parse_request(m)
	if not request.usage.is_empty(): return Printed(
		stderr: request.usage + "\n",
		status: 2,
	)
	if request.rust: return none

	cwd := canonicalize(working_directory().get_or(".")).get_or("")
	if cwd.is_empty(): return none

	expanded := expand_targets(cwd, request.targets)
	if expanded.rust: return none

	// Resolve every file first, so a file that cannot be read is reported before
	// anything is written.
	var found = Map[String, String]()
	var order = List[String]()
	var sources = Map[String, String]()
	var modes = Map[String, Int]()
	var failures = expanded.failures.clone()
	var bad = Map[String, Outcome]()

	for target in expanded.files:
		real := canonicalize(target)
		info := stat(target)

		if real.is_error() or info.is_error():
			failures.append(missing(shown_target(cwd, target)))
			continue

		absolute := real.get()
		if found.contains(absolute) or bad.contains(absolute): continue

		display := display_of(cwd, absolute)
		data := read_file(target).wait()

		if data.is_error():
			failures.append(
				failure_of(
					cwd,
					target,
					f"cannot read {display}: {data.err().message}",
				)
			)
			bad.add(absolute.clone(), failures[failures.length() - 1].clone())
			continue

		source := data.get().decode_utf8()

		if source.is_none():
			message := "source must be valid UTF-8; re-save the file with UTF-8 encoding"
			failures.append(
				Outcome(
					display.clone(),
					absolute.clone(),
					"error",
					Issue(
						"MS1001",
						"parse",
						message.clone(),
						1,
						1,
						0,
					),
					f"{display}:1:1: parse: {message}\nfmt only formats source that parses; fix the syntax error above, then re-run ms fmt {display}",
				)
			)
			continue

		found.add(absolute.clone(), display)
		order.append(absolute.clone())
		sources.add(absolute.clone(), source.get())
		modes.add(absolute.clone(), info.get().permissions)

	var ordered = List[String]()

	for absolute in order:
		var at = ordered.length()
		while at > 0 and found.get_or(absolute, "") < found.get_or(ordered[at - 1], ""): at -= 1
		ordered.insert(at, absolute.clone())

	var outcomes = failures.clone()
	var unique = 0

	for absolute in ordered:
		display := found.get_or(absolute, "")
		outcomes.append(
			check_one(
				display,
				absolute,
				sources.get_or(absolute, ""),
				request,
				modes.get_or(absolute, 420),
				unique,
			)
		)
		unique += 1

	var result = Printed()

	for outcome in outcomes:
		if (
			outcome.state == "error"
			or outcome.state == "needs_formatting"
			or outcome.state.is_empty()
		):
			result.status = 1
			if not request.json: result.stderr += outcome.message + "\n"

	if outcomes.is_empty() and not request.json:
		result.stderr += f"ms fmt: no .ms files found in {request.targets.join(", ")}\n"
	if request.json: result.stdout = document(outcomes)
	return result
