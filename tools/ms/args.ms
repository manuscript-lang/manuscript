// What the command tree parsed, as an `Invocation` for the source commands (`check`,
// `lint`, `build`, `emit`, `run`, `test`, `bench`, `inspect`, `diagram`, `profile`), and
// the checks on option values and combinations that the tree's schema cannot state.
// Every refusal is an Error whose message the caller prints on standard error before
// exiting with status 2.
import (
	Matches from "@std/cli/command.ms",
	exists, stat from "@std/os/fs.ms",
	Os, os from "@std/os/system.ms",
	compile from "@std/regex.ms",
	parse_duration from "@std/time.ms",

	quote from "./quote.ms",
)

// The `--view` names of `ms diagram`.
export fn views() List[String]:
	return [
		"overview", "calls", "effects", "errors", "modules", "flow", "scope", "tasks",
		"types", "ownership"
	]

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

fn usage(message: String) Void!:
	return error(Error(message))

// A directory argument selects the `ms.toml` inside it.
export fn resolve_input(command: String, filename: String) String!:
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

fn empty_input(command: String) Void!:
	return usage(
		f"ms {command}: an input argument is empty; pass a .ms file, directory, or ms.toml"
	)

fn on(m: Matches, name: String) Bool:
	if text := m.string_or_none(name): return text == "true"
	return false

fn positive(m: Matches, name: String) Void!:
	if value := m.int_or_none(name):
		if value <= 0: usage(f"invalid --{name}; use a positive integer")?
	return ok(void)

// The test and bench options the supervisor receives, as `--name=value` in a fixed
// order after the switches; each value is checked here.
fn selection_options(m: Matches) List[String]!:
	var options = List[String]()
	for name in ["list", "fail-fast", "ops"]:
		if on(m, name): options.append(f"--{name}")
	for name in ["test", "bench"]:
		for value in m.list(name): options.append(f"--test={value}")

	for name in ["match", "exclude"]:
		if value := m.string_or_none(name):
			compiled := compile(value)
			if compiled.is_error():
				usage(
					f"invalid --{name}: {compiled.err().message}; supply a valid regular expression"
				)?
			options.append(f"--{name}={value}")

	for name in ["repeat", "runs", "samples", "iterations"]:
		positive(m, name)?
		if value := m.string_or_none(name): options.append(f"--{name}={value}")

	for name in ["shuffle", "seed"]:
		if value := m.string_or_none(name): options.append(f"--{name}={value}")

	if value := m.string_or_none("time"):
		parsed := parse_duration(value)
		if parsed.is_error() or parsed.get().nanos < 1000000:
			usage(
				f"invalid --time {quote(value)}; use a duration of at least 1ms such as 200ms or 1s"
			)?
		options.append(f"--time={value}")

	if value := m.string_or_none("fuzz"):
		parsed := parse_duration(value)
		if parsed.is_error() or parsed.get().nanos <= 0:
			usage(
				f"invalid --fuzz {quote(value)}; use a positive duration such as 30s or 5m"
			)?
		options.append(f"--fuzz={value}")

	for name in ["baseline", "fail-over"]:
		if value := m.string_or_none(name): options.append(f"--{name}={value}")
	return ok(options)

// Reads the values the tree parsed for a source command: `m.path` is `ms <command>`.
// The file of a command that takes one resolves a directory to its ms.toml.
export fn invocation(m: Matches) Invocation!:
	command := m.path[1].clone()
	var inv = Invocation(command: command.clone())
	inv.analysis = command == "check" or command == "lint"

	var targets = m.list("targets")
	if file := m.string_or_none("file"): targets = [file]
	if targets.any(fn t: t.is_empty()): empty_input(command)?
	if not inv.analysis: targets[0] = resolve_input(command, targets[0])?
	inv.filename = targets[0].clone()
	inv.targets = targets
	inv.arguments = m.passthrough.clone()
	inv.output = m.string_or_none("output").get_or(
		m.string_or_none("out-dir").get_or("")
	)
	inv.link = m.list("link")
	inv.static_libc = on(m, "static")
	inv.structured = on(m, "json")
	inv.watch = on(m, "watch")
	inv.fix = on(m, "fix")
	inv.deny_warnings = on(m, "deny-warnings")
	inv.with_text = on(m, "with-text")
	inv.each = on(m, "each")
	inv.allocs = on(m, "allocs")
	inv.build_type_name = m.string_or_none("build-type").get_or("")
	inv.test_filter = m.string_or_none("filter").get_or("")
	inv.format = m.string_or_none("format").get_or("")
	inv.view = m.string_or_none("view").get_or("")
	inv.entity = m.string_or_none("entity").get_or("")
	inv.diff = m.string_or_none("diff").get_or("")
	positive(m, "depth")?
	positive(m, "top")?
	inv.depth = m.int_or_none("depth").get_or(0)
	inv.top = m.int_or_none("top").get_or(0)

	if value := m.string_or_none("timeout"):
		parsed := parse_duration(value)
		if parsed.is_error() or parsed.get().nanos < 0:
			usage(
				f"invalid --timeout {quote(value)}; use a duration such as 30s or 2m, or 0 to disable"
			)?
		inv.test_timeout = value

	inv.test_options = selection_options(m)?
	return ok(inv)

// Rejects option combinations the command does not accept and normalises what is left
// (`--view` aliases, the test arguments). Each problem is a cause and a fix.
export fn validate(var inv: Invocation) Void!:
	command := inv.command.clone()

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

	if command == "test" or command == "bench":
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
	if inv.fix and inv.watch:
		usage(f"--fix cannot be combined with --watch; use ms {command} <file> --fix")?
	if inv.with_text and not inv.structured:
		usage("--with-text requires --json; use ms check <file> --json --with-text")?
	if inv.each and not (inv.with_text and not inv.watch and not inv.fix):
		usage(
			"--each requires --json --with-text without --watch or --fix; use ms check a.ms b.ms --json --with-text --each"
		)?

	if not inv.build_type_name.is_empty():
		known := ["debug", "release", "minsizerel"]
		if not known.contains(inv.build_type_name.lower()):
			usage(
				f"unknown build type {quote(inv.build_type_name)}; expected Debug, Release, or MinSizeRel"
			)?

	if inv.static_libc and os() != Os.Linux:
		usage("--static links static musl, which only Linux has; remove the flag")?
	return ok(void)
