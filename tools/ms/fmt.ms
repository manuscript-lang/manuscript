// `ms fmt [--check] [--json] [--] <file.ms>...`: formats the files in place, or reports the ones
// that need it. The formatter is libms's (`ms_tool_format`,
// compiler/include/ms/tool.h), so a program that imports this module links
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
	relative from "@std/os/path.ms",
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

// The files `ms fmt` formats for each target: a `.ms` file is itself, a directory or an
// `ms.toml` is what libms finds there. none when the Rust command must answer.
fn expand_targets(targets: List[String]) List[String]?:
	var files = List[String]()

	for target in targets:
		if target.ends_with(".ms"):
			files.append(target.clone())
			continue

		// A workspace root without a `[project]` stands for its members, as in the
		// other commands.
		var manifests = [target.clone()]

		if members := root_members(target):
			manifests = []
			for member in members: manifests.append(member.manifest.clone())

		for manifest in manifests:
			found := ms_tool_discover(manifest)
			if found.is_error(): return none

			for path in found.get(): files.append(path.clone())

	return files

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

	if m.bool("drop-labels") or request.targets.contains(""):
		request.rust = true
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

	// Resolve every target first: a file that is not a plain readable `.ms` file is not
	// ours.
	var found = Map[String, String]()
	var order = List[String]()
	var sources = Map[String, String]()
	var modes = Map[String, Int]()
	expanded := expand_targets(request.targets)
	if expanded.is_none(): return none

	for target in expanded.get():
		real := canonicalize(target)
		info := stat(target)
		if real.is_error() or info.is_error() or not info.get().is_file(): return none

		data := read_file(target).wait()
		if data.is_error(): return none

		source := data.get().decode_utf8()
		if source.is_none(): return none

		absolute := real.get()
		if found.contains(absolute): continue

		display := display_of(cwd, absolute)
		found.add(absolute.clone(), display)
		order.append(absolute.clone())
		sources.add(absolute.clone(), source.get())
		modes.add(absolute.clone(), info.get().permissions)

	var ordered = List[String]()

	for absolute in order:
		var at = ordered.length()
		while at > 0 and found.get_or(absolute, "") < found.get_or(ordered[at - 1], ""): at -= 1
		ordered.insert(at, absolute.clone())

	var outcomes = List[Outcome]()
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
		if outcome.state == "error" or outcome.state == "needs_formatting":
			result.status = 1
			if not request.json: result.stderr += outcome.message + "\n"

	if request.json: result.stdout = document(outcomes)
	return result
