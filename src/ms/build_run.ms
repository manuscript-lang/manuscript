// `ms build FILE.ms [-o OUTPUT]` over libms (`ms_tool_build`, src/compiler/include/ms/tool.h). The C pipeline loads and
// checks the program, lowers it whole, compiles it with the pinned LLVM tools and links
// it. When it cannot give the answer the Rust command would (any diagnostic, a function
// the lowering does not cover, a program the loader does not read, a missing tool path)
// `run_build` returns none and the caller runs the Rust command. The tools are named by
// `MS_LLVM_TOOLS` (a directory with opt and llc), `MS_LLD`, `MS_LINKER_FILES` (the
// startup files of ms/build_link.h) and `MS_RT_LIB` (the runtime archive) until the C
// side fetches and embeds them.
import (
	stderr, stdout from "@std/io/io.ms",
	environment from "@std/os/env.ms",
	remove, stat, temporary_directory from "@std/os/fs.ms",
	SpawnOptions, Stdio, spawn from "@std/os/process.ms",

	Invocation from "./args.ms",
	check_rows from "./check_run.ms",
)

// Status 1 is a failed build (the message); status 2 is a program the C pipeline does
// not cover.
export enum BuildError:
	Failed(message: String)
	Unsupported(message: String)

extern fn ms_tool_build(
	target: String,
	output: String,
	runtime: String,
	tools: String,
	lld: String,
	files: String,
	release: Bool,
) List[String]!BuildError

extern fn ms_tool_build_tests(
	target: String,
	output: String,
	runtime: String,
	tools: String,
	lld: String,
	files: String,
	release: Bool,
	bench: Bool,
	extra: String,
) List[String]!BuildError

// The tools directory, `lld`, the linker's files and the runtime archive, or none while
// one is not named.
fn tool_paths(env: Map[String, String]) List[String]?:
	tools := env.get("MS_LLVM_TOOLS")?
	lld := env.get("MS_LLD")?
	files := env.get("MS_LINKER_FILES")?
	runtime := env.get("MS_RT_LIB")?
	return [tools.clone(), lld.clone(), files.clone(), runtime.clone()]

// How the C pipeline answered: built, or reported the program's diagnostics (the exit
// status 1 the Rust command gives), or left the command to the Rust one.
enum Built:
	Done
	Diagnosed
	Rust

// Whether a handover is only the program's own errors, which the C checker renders as
// the Rust command does.
fn is_diagnostic(error: BuildError) Bool:
	match error:
		Unsupported(message): return message.starts_with("a diagnostic")
		Failed(_message): return false

// Prints the errors of `target` the way `ms check` does; false when the C checker
// does not give them (a warning-only program is built by the Rust command).
fn report_diagnostics(target: String) Bool:
	rows := check_rows(target, false)
	if rows.is_none(): return false
	if rows.get()[2] != "1": return false

	stdout().write(rows.get()[0].clone()).get()
	stderr().write(rows.get()[1].clone()).get()
	return true

// What the C pipeline did with `inv`'s program for `output`.
fn built_in_c(inv: Invocation, output: String) Built:
	if inv.structured or inv.static_libc or inv.watch: return Built.Rust
	if not inv.link.is_empty(): return Built.Rust
	if inv.targets.length() > 1: return Built.Rust

	kind := inv.build_type_name.lower()
	if kind != "" and kind != "debug" and kind != "release": return Built.Rust

	target := if inv.targets.is_empty(): inv.filename.clone() else: inv.targets[0].clone()
	if not target.ends_with(".ms"): return Built.Rust

	vars := environment()
	if vars.is_error(): return Built.Rust

	env := vars.get()
	paths := tool_paths(env)
	if paths.is_none(): return Built.Rust

	// A failed or declined C build is the Rust command's to report, in its words.
	built := ms_tool_build(
		target,
		output,
		paths.get()[3],
		paths.get()[0],
		paths.get()[1],
		paths.get()[2],
		kind == "release",
	)

	if built.is_error():
		if env.contains("MS_DRIVER_TRACE"): trace(built.err())
		if is_diagnostic(built.err()) and report_diagnostics(target): return Built.Diagnosed

		return Built.Rust

	return Built.Done

// Builds the tests of `inv`'s program into `output` (and `<output>.tests`) in C. False when the C
// pipeline did not build them and the Rust command must: a diagnostic (Rust renders it), a test or
// the runner the lowering does not cover, an option C does not read, a missing tool path.
export fn build_tests_in_c(inv: Invocation, output: String, bench: Bool) Bool:
	if bench or inv.static_libc or inv.watch or not inv.link.is_empty(): return false
	if inv.tests.ops: return false

	kind := inv.build_type_name.lower()
	if kind != "" and kind != "debug" and kind != "release": return false

	vars := environment()
	if vars.is_error(): return false

	env := vars.get()
	paths := tool_paths(env)
	if paths.is_none(): return false

	extra := inv.targets.drop(1).join("\n")
	built := ms_tool_build_tests(
		inv.filename.clone(),
		output.clone(),
		paths.get()[3],
		paths.get()[0],
		paths.get()[1],
		paths.get()[2],
		kind == "release",
		bench,
		extra,
	)

	if built.is_error():
		if env.contains("MS_DRIVER_TRACE"): trace(built.err())
		return false

	return true

// The exit status, or none when the Rust command must run.
export fn run_build(inv: Invocation) Int?:
	shown := if inv.output.is_empty(): "program" else: inv.output.clone()

	// The Rust command makes the output's directory and refuses a directory as output.
	if directory(shown): return none
	if shown.contains("/") and not directory(shown.slice(0, shown.last_index_of("/")?)): return none

	built := built_in_c(inv, shown)
	if built == Built.Rust: return none
	if built == Built.Diagnosed: return 1

	stdout().write(f"Built {shown}\n").get()
	return 0

// `ms run`: the program is built into a temporary directory and started with the arguments after `--`; its exit
// status is the command's. None when the Rust command must run.
export fn run_program(inv: Invocation) Int?:
	root := temporary_directory("manuscript-run-")
	if root.is_error(): return none

	dir := root.get().clone()
	executable := f"{dir}/program"
	built := built_in_c(inv, executable)

	if built != Built.Done:
		void remove(dir, recursive: true)
		return if built == Built.Diagnosed: 1 else: none

	child := spawn(
		executable,
		inv.arguments,
		SpawnOptions(
			stdin: Stdio.Inherit,
			stdout: Stdio.Inherit,
			stderr: Stdio.Inherit,
		),
	)
	var status = 1
	if child.is_ok(): status = child.get().wait().get_or(1)
	void remove(dir, recursive: true)
	return status

// Says on standard error why the C build left the command to the Rust one.
fn trace(error: BuildError) Void:
	match error:
		Failed(message): stderr().write(f"ms build: C build failed: {message}\n").get()
		Unsupported(message): stderr().write(
			f"ms build: handed to Rust: {message}\n"
		).get()

fn directory(path: String) Bool:
	info := stat(path)
	return info.is_ok() and info.get().is_directory()
