// The `ms` command line: dispatch, help, usage errors and the default-target rule. Run
// it as
// `ms run tools/ms/main.ms -- <ms arguments>`.
//
// Exit statuses: 0 success; 1 the command ran and failed; 2 usage error (nothing was
// run); and the program's own status for `run`. Commands that still need a compiler
// stage that is not ported are handed whole to the Rust `ms` named by $MS_RUST_CLI
// (default `ms-rust` on the PATH), with the same streams; `MS_CLI_PLAN=1` prints the
// choice instead of running it.
import (
	Command, Matches, Parsed from "@std/cli/command.ms",
	edit_distance from "@std/data/diff.ms",
	stderr, stdout from "@std/io/io.ms",
	arguments, environment from "@std/os/env.ms",
	exists, read_file from "@std/os/fs.ms",
	SpawnOptions, Stdio, spawn from "@std/os/process.ms",

	Invocation, invocation, validate from "./args.ms",
	rust_cli from "./bridge.ms",
	spec, takes_value from "./cli.ms",
	run_explain from "./explain.ms",
	Printed, run_fmt from "./fmt.ms",
	run_init from "./init.ms",
	run_add, run_install, run_remove from "./install.ms",
	run_profile from "./profile.ms",
	run_members from "./test/members.ms",
	run_bench, run_test from "./test/run.ms",
	run_verify from "./verify.ms",
	root_members from "./workspace.ms",
)

fn out(text: String) Void:
	stdout().write(text).get()

fn err(text: String) Void:
	stderr().write(text).get()

fn command_names(root: Command) List[String]:
	return root.children.map(fn child: child.name.clone()).concat(["help"])

fn unknown_command(root: Command, name: String) Void:
	err(f"unknown command: {name}\n")

	var best = ""
	var best_distance = 3

	for candidate in command_names(root):
		distance := edit_distance(name, candidate)

		if distance < best_distance:
			best = candidate.clone()
			best_distance = distance

	if not best.is_empty():
		err(f"Did you mean 'ms {best}'?\n")
	else if (
		name.ends_with(".ms")
		or name.ends_with(".toml")
		or name.contains("/")
		or name.contains("\\")
	):
		err(
			f"'{name}' looks like a path; commands come first, e.g. 'ms run {name}' or 'ms check {name}'.\n"
		)

	err(f"Commands: {command_names(root).join(", ")}. Run 'ms --help' for details.\n")

fn project_commands() List[String]:
	return [
		"check", "lint", "build", "emit", "run", "test", "bench", "fmt", "verify",
		"inspect", "diagram", "review", "profile"
	]

fn target_list_commands() List[String]:
	return ["check", "lint", "fmt", "verify"]

// Inside a project directory, `ms run` means `ms run ms.toml`: when the command names
// no target (nothing after it, or only options and `-- program arguments`), insert the
// manifest in the current directory. A target written after options
// (`ms run --json main.ms`,
// `ms check -- main.ms`) replaces the default and, where the command wants its file first,
// moves ahead of the options. Returns none when the arguments stay as they are.
fn default_project_target(root: Command, args: List[String]) List[String]?:
	command := args[0].clone()
	if not project_commands().contains(command): return none
	if args.length() > 1 and args[1] != "--" and not args[1].starts_with("-"): return none

	lists := target_list_commands().contains(command)

	// Positions of the arguments that are inputs, before and after any `--`.
	var inputs = List[Int]()
	var dashes = args.length()
	var i = 1

	while i < args.length():
		arg := args[i].clone()

		if arg == "--":
			dashes = i
			break

		if arg.starts_with("-"):
			if takes_value(root, command, arg): i += 1
		else:
			inputs.append(i)

		i += 1

	if lists:
		for at in (dashes + 1)..args.length(): inputs.append(at)

	if first := inputs.first():
		// `fmt` and `verify` take options anywhere, and `--` leading the arguments already
		// puts the file first.
		if command == "fmt" or command == "verify" or dashes == 1: return none

		// Moving an input out of `--` must preserve its path meaning, including names
		// such as `--help` that the early help scan otherwise consumes.
		target := if args[first].starts_with("-"): f"./{args[first]}" else: args[first].clone()
		var result = [command.clone(), target]

		if lists:
			// Further inputs follow `--` so they are not read as options.
			for at in 1..args.length():
				if at == dashes or inputs.contains(at): continue

				result.append(args[at].clone())

			if inputs.length() > 1:
				result.append("--")
				for at in inputs.drop(1): result.append(args[at].clone())
		else:
			for at in 1..args.length():
				if at != first: result.append(args[at].clone())

		return result

	if not exists("ms.toml").get_or(false): return none

	var result = [command.clone(), "ms.toml"]
	result.extend(args.drop(1))
	return result

// Hands the whole command to the Rust `ms`.
fn delegate(args: List[String]) Int:
	env := environment().get_or(Map[String, String]())
	program := rust_cli()

	if env.contains("MS_CLI_PLAN"):
		out(f"delegate {args.join(" ")}\n")
		return 0

	child := spawn(
		program,
		args,
		SpawnOptions(
			stdin: Stdio.Inherit,
			stdout: Stdio.Inherit,
			stderr: Stdio.Inherit,
		),
	)

	if child.is_error():
		err(f"ms: cannot run {program}\n")
		return 70

	return child.get().wait().get_or(70)

fn run_explain_command(args: List[String]) Int:
	got := run_explain(args)
	out(got.stdout)
	err(got.stderr)
	return got.status

fn is_source_command(command: String) Bool:
	return [
		"check", "lint", "build", "emit", "run", "test", "bench", "inspect", "diagram",
		"profile"
	].contains(command)

// Runs `ms test` or `ms bench` in the front; none when the Rust command line must: a
// `--watch`, several targets that are not all manifests, or a workspace root whose members
// need the Rust command line to explain them.
fn run_tests(args: List[String], inv: Invocation) Int?:
	if inv.watch: return none

	bench := inv.command == "bench"
	manifests := inv.targets.filter(fn target: target.ends_with("ms.toml"))

	if inv.targets.length() > 1:
		if bench: return none
		if manifests.length() == inv.targets.length(): return run_members(
			args,
			inv,
			manifests,
		)

	if not inv.filename.ends_with("ms.toml"):
		return if bench: run_bench(inv) else: run_test(inv)

	text := read_file(inv.filename).wait()
	if text.is_error(): return none

	members := root_members(inv.filename)

	if members.is_none():
		if text.get().decode_utf8().get_or("").contains("[workspace]"): return none
		return if bench: run_bench(inv) else: run_test(inv)

	var found = List[String]()
	for member in members.get(): found.append(member.manifest.clone())

	if bench:
		var names = List[String]()
		for member in members.get(): names.append(member.name.clone())
		err(
			f"ms bench: {inv.filename} is a workspace root; name one member's ms.toml instead, such as {found[0]} (members: {names.join(", ")})\n"
		)
		return 2

	if found.length() > 1: return run_members(args, inv, found)

	var single = inv.clone()
	single.filename = found[0].clone()
	single.targets = [found[0].clone()]
	return run_test(single)

fn run_source_command(args: List[String], matches: Matches) Int:
	parsed := invocation(matches)

	if parsed.is_error():
		err(parsed.err().message + "\n")
		return 2

	var inv = parsed.get()
	checked := validate(inv)

	if checked.is_error():
		err(checked.err().message + "\n")
		return 2

	if inv.command == "profile": return run_profile(inv)

	if inv.command == "test" or inv.command == "bench":
		if status := run_tests(args, inv): return status
	return delegate(args)

export fn run(given: List[String]) Int:
	root := spec()
	if given.length() == 1 and given[0] == "--version": return delegate(given)

	if given.length() > 0 and not given[0].starts_with("-") and given[0] != "help":
		if root.child(given[0]).is_none():
			unknown_command(root, given[0])
			return 2

	var args = given.clone()
	if not given.is_empty():
		if defaulted := default_project_target(root, given): args = defaulted

	parsed := root.parse(args)

	if parsed.is_error():
		hint := if args.is_empty() or args[0].starts_with("-") or args[0] == "help": "ms --help" else: f"ms help {args[0]}"
		err(parsed.err().message + f"\nRun '{hint}' for usage.\n")
		return 2

	match parsed.get():
		Help(text):
			out(text)
			return 0
		Run(matches): return dispatch(args, matches)

// Runs the command `matches` selected, with `args` as the command line after the
// default target was applied.
fn dispatch(args: List[String], matches: Matches) Int:
	command := matches.path[1].clone()
	if command == "init": return run_init(args.drop(1))
	if command == "explain": return run_explain_command(args.drop(1))
	if command == "verify": return run_verify(args.drop(1))

	if command == "fmt":
		if done := run_fmt(args.drop(1)):
			out(done.stdout)
			err(done.stderr)
			return done.status

		return delegate(args)

	if command == "install" or command == "add" or command == "remove":
		if done := run_manifest_command(args):
			out(done.stdout)
			err(done.stderr)
			return done.status

		return delegate(args)

	if is_source_command(command): return run_source_command(args, matches)

	return delegate(args)

fn run_manifest_command(args: List[String]) Printed?:
	rest := args.drop(1)
	if args[0] == "install": return run_install(rest)
	if args[0] == "add": return run_add(rest)

	return run_remove(rest)

fn main() Int:
	return run(arguments())
