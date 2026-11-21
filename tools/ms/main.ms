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
	Command, Matches from "@std/cli/command.ms",
	stderr, stdout from "@std/io/io.ms",
	environment from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
	SpawnOptions, Stdio, spawn from "@std/os/process.ms",

	Invocation, invocation, validate from "./args.ms",
	rust_cli from "./bridge.ms",
	run_check from "./check_run.ms",
	command_line, rust_arguments, spec from "./cli.ms",
	run_explain from "./explain.ms",
	Printed, run_fmt from "./fmt.ms",
	run_init_command from "./init.ms",
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

fn run_explain_command(matches: Matches) Int:
	got := run_explain(matches)
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
fn run_tests(root: Command, matches: Matches, inv: Invocation) Int?:
	if inv.watch: return none

	bench := inv.command == "bench"
	manifests := inv.targets.filter(fn target: target.ends_with("ms.toml"))

	if inv.targets.length() > 1:
		if bench: return none
		if manifests.length() == inv.targets.length(): return run_members(
			inv,
			manifests,
			member_lines(root, matches, manifests),
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

	if found.length() > 1: return run_members(
		inv,
		found,
		member_lines(root, matches, found),
	)

	var single = inv.clone()
	single.filename = found[0].clone()
	single.targets = [found[0].clone()]
	return run_test(single)

// The command line of each manifest's own run.
fn member_lines(
	root: Command,
	matches: Matches,
	manifests: List[String],
) List[List[String]]:
	return manifests.map(fn manifest: rust_arguments(root, matches, [manifest.clone()]))

fn run_source_command(root: Command, matches: Matches) Int:
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

	if inv.command == "check":
		if status := run_check(inv): return status
	if inv.command == "check":
		if status := run_check(inv): return status
	if inv.command == "test" or inv.command == "bench":
		if status := run_tests(root, matches, inv): return status
	return delegate(rust_arguments(root, matches))

export fn run(given: List[String]) Int:
	root := spec()
	parsed := root.parse(given)

	if parsed.is_error():
		err(parsed.err().message + "\n" + root.usage_hint(given) + "\n")
		return 2

	match parsed.get():
		Help(text):
			out(text)
			return 0
		Run(matches): return dispatch(root, matches)

// Runs the command `matches` selected.
fn dispatch(root: Command, matches: Matches) Int:
	if matches.path.length() == 1: return delegate(["--version"])

	command := matches.path[1].clone()
	if command == "init": return run_init_command(matches)
	if command == "explain": return run_explain_command(matches)
	if command == "verify": return run_verify(matches)

	if command == "fmt":
		if done := run_fmt(matches):
			out(done.stdout)
			err(done.stderr)
			return done.status

		return delegate(rust_arguments(root, matches))

	if command == "install" or command == "add" or command == "remove":
		done := run_manifest_command(command, matches)
		out(done.stdout)
		err(done.stderr)
		return done.status

	if is_source_command(command): return run_source_command(root, matches)

	return delegate(rust_arguments(root, matches))

fn run_manifest_command(command: String, matches: Matches) Printed:
	if command == "install": return run_install(matches)
	if command == "add": return run_add(matches)

	return run_remove(matches)

fn main() Int:
	return run(command_line())
