// Option parsing and validation for the source commands (`check`, `lint`, `build`,
// `emit`,
// `run`, `test`, `bench`, `inspect`, `diagram`, `profile`), and the default-target rule for
// commands that take a project. Every refusal is an Error whose message the caller
// prints on standard error before exiting with status 2.
import (
	environment from "@std/os/env.ms",
	exists, stat from "@std/os/fs.ms",
	Os, os from "@std/os/system.ms",
	compile from "@std/regex.ms",
	parse_duration from "@std/time.ms",

	quote from "./quote.ms",
)

// Long options that take a value (also accepted as `--flag=value`).
export fn value_options() List[String]:
	return [
		"-o", "--output", "--out-dir", "--build-type", "--timeout", "--filter",
		"--test", "--bench", "--match", "--exclude", "--repeat", "--shuffle", "--runs",
		"--seed", "--fuzz", "--time", "--samples", "--iterations", "--baseline",
		"--fail-over", "--format", "--view", "--entity", "--depth", "--diff", "--top",
		"--link"
	]

// The `--view` names of `ms diagram`.
export fn views() List[String]:
	return [
		"overview", "calls", "effects", "errors", "modules", "flow", "scope", "tasks",
		"types", "ownership"
	]

// Commands that accept `--json`.
fn json_commands() List[String]:
	return [
		"check", "lint", "test", "bench", "run", "build", "profile", "inspect",
		"diagram", "emit", "fmt", "verify", "search_symbol"
	]

// Commands that execute a program and can forward its arguments after `--`.
fn program_commands() List[String]:
	return ["run", "test", "bench", "profile"]

// Commands that take a source file or project and default to `./ms.toml`.
fn project_commands() List[String]:
	return [
		"check", "lint", "build", "emit", "run", "test", "bench", "fmt", "verify",
		"inspect", "diagram", "review", "profile"
	]

// Commands whose arguments after `--` are more inputs, not program arguments.
fn target_list_commands() List[String]:
	return ["check", "lint", "fmt", "verify"]

export type Invocation:
	command: String = ""
	filename: String = ""
	// `check` and `lint` accept many targets.
	analysis: Bool = false
	targets: List[String] = []
	output: String = ""
	// `--link`: extra objects and static libraries for `extern fn` symbols.
	link: List[String] = []
	static_libc: Bool = false
	format_check: Bool = false
	structured: Bool = false
	watch: Bool = false
	fix: Bool = false
	deny_warnings: Bool = false
	with_text: Bool = false
	each: Bool = false
	build_type_name: String = ""
	test_timeout: String = ""
	test_filter: String = ""
	test_options: List[String] = []
	format: String = ""
	view: String = ""
	entity: String = ""
	diff: String = ""
	depth: Int = 0
	top: Int = 0
	allocs: Bool = false
	// Forwarded to the program after `--`.
	arguments: List[String] = []

fn is_one_of(command: String, names: List[String]) Bool:
	return names.contains(command)

fn usage(message: String) Void!:
	return error(Error(message))

// Whether `flag` (without an inline `=value`) is followed by its value in the next
// argument.
export fn takes_value(flag: String) Bool:
	return (
		value_options().contains(flag)
		or ["--limit", "--explain", "--effect"].contains(flag)
	)

// `--help` scanning: a flag value is not a help request, even if spelled `--help`.
export fn requests_help(args: List[String]) Bool:
	var i = 0

	while i < args.length():
		arg := args[i].clone()
		if arg == "--": return false
		if arg == "-h" or arg == "--help": return true

		if takes_value(arg): i += 1
		i += 1

	return false

// `--name=value` is recognised only for long options that take values.
type Split:
	name: String
	value: String
	inline: Bool

fn split_value_option(arg: String) Split:
	if parts := arg.split_once("="):
		if parts.before.starts_with("--") and value_options().contains(parts.before):
			return Split(
				name: parts.before.clone(),
				value: parts.after.clone(),
				inline: true,
			)
	return Split(name: arg.clone(), value: "", inline: false)

// A flag's value and the index of the last argument it used.
type Taken:
	text: String
	index: Int

// Consumes a split value or uses its inline spelling; empty values are refused.
fn required_value(args: List[String], index: Int, split: Split) Taken?:
	var at = index
	var text = split.value.clone()

	if not split.inline:
		at += 1
		if at >= args.length(): return none

		text = args[at].clone()

	if text.is_empty(): return none

	return Taken(text: text, index: at)

// A directory argument selects the `ms.toml` inside it.
fn resolve_input(command: String, filename: String) String!:
	info := stat(filename)
	if info.is_error(): return ok(filename.clone())
	if not info.get().is_directory(): return ok(filename.clone())

	manifest := if filename.ends_with("/"): f"{filename}ms.toml" else: f"{filename}/ms.toml"
	if stat(manifest).is_error():
		return error(
			Error(
				f"ms {command}: {filename} is a directory without an ms.toml; pass a .ms file or a project ms.toml, e.g. ms {command} ms.toml"
			)
		)

	return ok(manifest)

fn manifest_hint() String:
	if exists("ms.toml").get_or(false): return ""
	return "; with no file, ms uses ./ms.toml, which does not exist here, so pass a .ms file or a project ms.toml"

fn empty_input(command: String) Void!:
	return usage(
		f"ms {command}: an input argument is empty; pass a .ms file, directory, or ms.toml"
	)

// Reads the command, its input file and options. `args[0]` is the command and `args[1]`
// its first argument.
export fn parse_invocation(args: List[String]) Invocation!:
	var inv = Invocation(command: args[0].clone(), filename: args[1].clone())
	if inv.filename.is_empty():
		usage(
			f"ms {inv.command}: the file argument is empty; pass a .ms file, directory, or ms.toml"
		)?
	inv.analysis = is_one_of(inv.command, ["check", "lint"])

	var first = 1
	var positional = false

	if inv.analysis and inv.filename == "--":
		if args.length() == 2:
			usage(
				f"ms {inv.command}: missing a target; pass .ms files, directories, or ms.toml"
			)?
		first = 2
		inv.filename = args[2].clone()
		positional = true

	if inv.filename.starts_with("-") and inv.filename != "--" and not positional:
		usage(
			f"unknown option {inv.filename} for ms {inv.command}; run 'ms help {inv.command}' for its options (put the file first, then options{manifest_hint()})"
		)?
	if not inv.analysis: inv.filename = resolve_input(inv.command, inv.filename)?
	inv.targets = [inv.filename.clone()]
	parse_options(inv, args, first, positional)?
	if inv.analysis and inv.targets.any(fn t: t.is_empty()): empty_input(inv.command)?
	return ok(inv)

fn path_requirement(flag: String) String:
	example := if flag == "--out-dir": "profile-bundle" else: "out.txt"
	return f"{flag} requires a path argument, e.g. {flag} {example}"

fn set_path(var inv: Invocation, flag: String, value: String) Void!:
	if flag == "--out-dir" and inv.command != "profile":
		usage(
			f"--out-dir is valid only for ms profile, not ms {inv.command}; use -o for commands that write a file"
		)?
	if flag != "--out-dir" and inv.command == "profile":
		usage(
			f"{flag} is not valid for ms profile; use --out-dir for the bundle directory"
		)?
	inv.output = value.clone()
	return ok(void)

fn positive_int(text: String) Bool:
	if value := text.parse_int(): return value > 0
	return false

fn parse_options(
	var inv: Invocation,
	args: List[String],
	first: Int,
	positional: Bool,
) Void!:
	var i = first + 1

	while i < args.length():
		if positional:
			inv.targets.append(args[i].clone())
			i += 1
			continue

		split := split_value_option(args[i])
		flag := split.name.clone()

		if flag == "--":
			if inv.analysis:
				inv.targets.extend(args.slice(i + 1, args.length())?)
			else:
				inv.arguments = args.slice(i + 1, args.length())?

			return ok(void)

		if flag == "--watch": inv.watch = true
		else if flag == "--fix": inv.fix = true
		else if flag == "--static": inv.static_libc = true
		else if flag == "--deny-warnings": inv.deny_warnings = true
		else if flag == "--with-text": inv.with_text = true
		else if flag == "--each": inv.each = true
		else if flag == "--check": inv.format_check = true
		else if flag == "--json": inv.structured = true
		else if flag == "--allocs": inv.allocs = true
		else if flag == "--build-type":
			taken := required_value(args, i, split).ok_or(
				Error(
					"--build-type requires a build type; use Debug, Release, or MinSizeRel"
				)
			)?
			if not inv.build_type_name.is_empty():
				usage(
					"--build-type may only be specified once; remove the duplicate flag"
				)?
			inv.build_type_name = taken.text.clone()
			i = taken.index
		else if flag == "--list" or flag == "--fail-fast" or flag == "--ops":
			inv.test_options.append(flag.clone())
		else if [
			"--test", "--match", "--exclude", "--repeat", "--shuffle", "--runs",
			"--seed", "--fuzz", "--time", "--samples", "--iterations", "--bench",
			"--baseline", "--fail-over"
		].contains(flag):
			taken := required_value(args, i, split).ok_or(
				Error(
					f"{flag} requires a value; run 'ms help test' for examples"
				)
			)?
			i = taken.index

			value := taken.text.clone()

			if flag == "--match" or flag == "--exclude":
				compiled := compile(value)
				if compiled.is_error():
					usage(
						f"invalid {flag}: {compiled.err().message}; supply a valid regular expression"
					)?

			if (
				[
					"--repeat", "--runs", "--samples", "--iterations"
				].contains(flag)
				and not positive_int(value)
			):
				usage(f"invalid {flag}; use a positive integer")?
			if ["--shuffle", "--seed"].contains(flag) and value.parse_int().is_none():
				usage(f"invalid {flag}; use an integer seed")?

			if flag == "--time":
				parsed := parse_duration(value)
				if parsed.is_error() or parsed.get().nanos < 1000000:
					usage(
						f"invalid --time {quote(value)}; use a duration of at least 1ms such as 200ms or 1s"
					)?

			if flag == "--fuzz":
				parsed := parse_duration(value)
				if parsed.is_error() or parsed.get().nanos <= 0:
					usage(
						f"invalid --fuzz {quote(value)}; use a positive duration such as 30s or 5m"
					)?

			// `--bench` names a bench the way `--test` names a test.
			name := if flag == "--bench": "--test" else: flag.clone()
			inv.test_options.append(f"{name}={value}")
		else if flag == "--timeout" or flag == "--filter":
			example := if flag == "--timeout": "--timeout 30s" else: "--filter \"test name\""
			taken := required_value(args, i, split).ok_or(
				Error(f"{flag} requires a value, e.g. {example}")
			)?
			i = taken.index

			if flag == "--filter":
				inv.test_filter = taken.text.clone()
			else:
				parsed := parse_duration(taken.text)
				if parsed.is_error() or parsed.get().nanos < 0:
					usage(
						f"invalid --timeout {quote(taken.text)}; use a duration such as 30s or 2m, or 0 to disable"
					)?
				inv.test_timeout = taken.text.clone()
		else if flag == "--format":
			taken := required_value(args, i, split).ok_or(
				Error("--format requires a name, e.g. --format mermaid")
			)?
			i = taken.index
			inv.format = taken.text.clone()
		else if ["--view", "--entity", "--depth", "--diff", "--top"].contains(flag):
			help := if flag == "--top": "profile" else: "diagram"
			taken := required_value(args, i, split).ok_or(
				Error(
					f"{flag} requires a value; run 'ms help {help}' for examples"
				)
			)?
			i = taken.index

			if flag == "--view": inv.view = taken.text.clone()
			else if flag == "--entity": inv.entity = taken.text.clone()
			else if flag == "--diff": inv.diff = taken.text.clone()
			else:
				if not positive_int(taken.text): usage(
					f"invalid {flag}; use a positive integer"
				)?

				number := taken.text.parse_int().get_or(0)

				if flag == "--depth": inv.depth = number
				else: inv.top = number
		else if flag == "--link":
			taken := required_value(args, i, split).ok_or(
				Error(
					"--link requires a path argument, e.g. --link native/libgreet.a"
				)
			)?
			i = taken.index
			inv.link.append(taken.text.clone())
		else if flag == "-o" or flag == "--output" or flag == "--out-dir":
			taken := required_value(args, i, split).ok_or(
				Error(path_requirement(flag))
			)?
			i = taken.index
			set_path(inv, flag, taken.text)?
		else:
			arg := args[i].clone()

			if not arg.starts_with("-"):
				if inv.analysis or inv.command == "test":
					if arg.is_empty(): empty_input(inv.command)?
					inv.targets.append(arg.clone())
					i += 1
					continue

				fix := if is_one_of(inv.command, program_commands()): "arguments for the program go after --" else: "remove the extra argument"
				usage(
					f"unexpected extra argument {arg} (ms {inv.command} takes one file; {fix})"
				)?

			hint := if is_one_of(inv.command, program_commands()): " (arguments for the program go after --)" else: ""
			usage(
				f"unknown option {arg} for ms {inv.command}; run 'ms help {inv.command}' for its options{hint}"
			)?

		i += 1

	return ok(void)

fn invalid_flag(command: String, format_check: Bool, structured: Bool) String:
	if format_check and command != "fmt": return f"--check is valid only for ms fmt, not ms {command}"
	if structured:
		return f"--json is valid only for ms {json_commands().join(", ")}, not ms {command}"

	return f"an option is not valid for ms {command}"

// The first test option whose flag is one of `names`.
fn only(inv: Invocation, names: List[String]) String?:
	for option in inv.test_options:
		var flag = option.clone()
		if parts := option.split_once("="): flag = parts.before.clone()
		if names.contains(flag): return flag

	return none

// Rejects option combinations the command does not accept and normalises what is left
// (`--view` aliases, the test arguments). Each problem is a cause and a fix.
export fn validate(var inv: Invocation) Void!:
	command := inv.command.clone()
	help_hint := f"run 'ms help {command}' for its options"
	if not is_one_of(
		command,
		[
			"check", "lint", "inspect", "diagram", "emit", "build", "run", "profile",
			"test", "bench"
		],
	):
		return error(Error("unknown command: " + command))

	if not inv.arguments.is_empty() and not is_one_of(command, program_commands()):
		usage(f"ms {command} does not run a program; remove the arguments after --")?
	if not inv.format.is_empty() and command != "diagram":
		usage(
			f"--format is valid only for ms diagram and ms review, not ms {command}; run 'ms help {command}' for its options"
		)?
	if (
		(
			not inv.view.is_empty()
			or not inv.entity.is_empty()
			or inv.depth != 0
			or not inv.diff.is_empty()
		)
		and command != "diagram"
	):
		usage(
			f"--view, --entity, --depth, and --diff are valid only for ms diagram, not ms {command}; run 'ms help {command}' for its options"
		)?
	if inv.allocs and command != "profile":
		usage(f"--allocs is valid only for ms profile, not ms {command}; {help_hint}")?
	if inv.top != 0 and command != "profile":
		usage(f"--top is valid only for ms profile, not ms {command}; {help_hint}")?

	if inv.view == "class": inv.view = "types"
	else if inv.view == "mutability": inv.view = "ownership"

	if not inv.view.is_empty() and not views().contains(inv.view):
		usage(
			f"unknown --view {quote(inv.view)} for ms diagram; use {views().join(", ")}"
		)?
	if (
		not inv.diff.is_empty()
		and inv.view.is_empty()
		and inv.entity.is_empty()
		and inv.format != "html"
	):
		usage(
			"--diff marks a scoped view; add --view or --entity, e.g. ms diagram ms.toml --view flow --entity save --diff change.patch"
		)?
	if inv.depth != 0 and inv.view.is_empty() and inv.entity.is_empty():
		usage("--depth needs --view or --entity; run 'ms help diagram' for examples")?
	if command == "diagram" and inv.structured and not inv.format.is_empty():
		usage("--json and --format cannot be combined; --json emits the diagram tree")?
	if (
		command == "diagram"
		and inv.format == "html"
		and (not inv.view.is_empty() or not inv.entity.is_empty())
	):
		usage("--format html covers every view in one page; drop --view and --entity")?
	if (
		command == "diagram"
		and not inv.format.is_empty()
		and inv.format != "ascii"
		and inv.format != "mermaid"
		and inv.format != "html"
	):
		usage(
			f"unknown --format {quote(inv.format)} for ms diagram; use ascii, mermaid, or html"
		)?
	if (
		not inv.output.is_empty()
		and not is_one_of(
			command,
			["build", "emit", "inspect", "diagram", "profile"],
		)
	):
		usage(
			f"-o and --output are valid only for ms build, emit, inspect, diagram, or profile, not ms {command}; run 'ms help {command}' for its options"
		)?
	if (
		(
			not inv.test_timeout.is_empty()
			or not inv.test_filter.is_empty()
			or not inv.test_options.is_empty()
		)
		and not is_one_of(command, ["test", "bench"])
	):
		usage(
			f"test selection options are valid only for ms test and ms bench, not ms {command}; run 'ms help {command}' for the options this command accepts"
		)?
	if command == "test":
		if flag := only(
			inv,
			[
				"--time", "--samples", "--iterations", "--baseline", "--fail-over",
				"--ops"
			],
		):
			usage(
				f"{flag} is valid only for ms bench; run 'ms help test' for the options this command accepts"
			)?
	if command == "bench":
		if flag := only(inv, ["--runs", "--seed", "--fuzz", "--shuffle"]):
			usage(
				f"{flag} is valid only for ms test; run 'ms help bench' for the options this command accepts"
			)?

	if is_one_of(command, ["test", "bench"]):
		var test_args = inv.test_options.clone()
		if not inv.test_timeout.is_empty(): test_args.append(
			f"--timeout={inv.test_timeout}"
		)
		if not inv.test_filter.is_empty(): test_args.append(
			f"--filter={inv.test_filter}"
		)

		if not inv.arguments.is_empty():
			test_args.append("--")
			test_args.extend(inv.arguments.clone())

		inv.arguments = test_args

	if inv.watch and inv.structured:
		usage(
			"--json cannot be combined with --watch; remove --watch for one versioned result"
		)?
	if inv.fix and (not is_one_of(command, ["check", "lint"]) or inv.watch):
		usage(
			f"--fix requires check or lint without --watch, not {command}; use ms check <file> --fix"
		)?
	if inv.with_text and (command != "check" or not inv.structured):
		usage(
			f"--with-text requires check --json, not {command}; use ms check <file> --json --with-text"
		)?
	if (
		inv.each
		and not (
			command == "check"
			and inv.structured
			and inv.with_text
			and not inv.watch
			and not inv.fix
		)
	):
		usage(
			"--each requires check --json --with-text without --watch or --fix; use ms check a.ms b.ms --json --with-text --each"
		)?
	if inv.deny_warnings and command != "lint":
		usage(
			f"--deny-warnings requires lint, not {command}; use ms lint <file> --deny-warnings"
		)?
	if inv.watch and not is_one_of(command, ["check", "lint", "run", "test"]):
		usage(
			f"--watch requires check, lint, run, or test, not {command}; use ms check <file> --watch or ms run <file> --watch"
		)?
	if (
		(inv.format_check and command != "fmt")
		or (inv.structured and not is_one_of(command, json_commands()))
	):
		usage(
			f"{invalid_flag(command, inv.format_check, inv.structured)}; run 'ms help {command}' for the options this command accepts"
		)?

	if not inv.build_type_name.is_empty():
		known := ["debug", "release", "minsizerel"]
		if not known.contains(inv.build_type_name.lower()):
			usage(
				f"unknown build type {quote(inv.build_type_name)}; expected Debug, Release, or MinSizeRel"
			)?

	if inv.static_libc and not is_one_of(command, ["build", "run", "test", "bench"]):
		usage(
			f"--static requires build, run, test, or bench, not {command}; remove the flag"
		)?
	if inv.static_libc and os() != Os.Linux:
		usage("--static links static musl, which only Linux has; remove the flag")?
	if (
		not inv.link.is_empty()
		and not is_one_of(command, ["build", "run", "test", "bench"])
	):
		usage(
			f"--link requires build, run, test, or bench, not {command}; remove the flag"
		)?
	if (
		not inv.build_type_name.is_empty()
		and not is_one_of(command, ["build", "run", "test", "bench", "profile"])
	):
		usage(
			f"--build-type requires build, run, test, bench, or profile, not {command}; remove the flag"
		)?
	return ok(void)
