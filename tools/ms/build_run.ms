// `ms build FILE.ms [-o OUTPUT]` over libms (`ms_tool_build`, compiler/include/ms/tool.h). The C pipeline loads and
// checks the program, lowers it whole, compiles it with the pinned LLVM tools and links it. When it cannot give the
// answer the Rust command would (any diagnostic, a function the lowering does not cover, a program the loader does
// not read, a missing tool path) `run_build` returns none and the caller runs the Rust command.
// The tools are named by `MS_LLVM_TOOLS` (a directory with opt and llc), `MS_LLD`, `MS_LINKER_FILES` (the startup
// files of ms/build_link.h) and `MS_RT_LIB` (the runtime archive) until the C side fetches and embeds them.
import (
	environment from "@std/os/env.ms",
	remove, stat, temporary_directory from "@std/os/fs.ms",
	SpawnOptions, Stdio, spawn from "@std/os/process.ms",
	stderr, stdout from "@std/io/io.ms",

	Invocation from "./args.ms",
)

// Status 1 is a failed build (the message); status 2 is a program the C pipeline does not cover.
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

// The tools directory, `lld`, the linker's files and the runtime archive, or none while one is not named.
fn tool_paths(env: Map[String, String]) List[String]?:
	tools := env.get("MS_LLVM_TOOLS")?
	lld := env.get("MS_LLD")?
	files := env.get("MS_LINKER_FILES")?
	runtime := env.get("MS_RT_LIB")?
	return [tools.clone(), lld.clone(), files.clone(), runtime.clone()]

// Whether the C pipeline built `inv`'s program into `output`; false when the Rust command must build it.
fn built_in_c(inv: Invocation, output: String) Bool:
	if inv.structured or inv.static_libc or inv.watch: return false
	if not inv.link.is_empty(): return false
	if inv.targets.length() > 1: return false

	kind := inv.build_type_name.lower()
	if kind != "" and kind != "debug" and kind != "release": return false

	target := if inv.targets.is_empty(): inv.filename.clone() else: inv.targets[0].clone()
	if not target.ends_with(".ms"): return false

	vars := environment()
	if vars.is_error(): return false

	env := vars.get()
	paths := tool_paths(env)
	if paths.is_none(): return false

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
		return false

	return true

// The exit status, or none when the Rust command must run.
export fn run_build(inv: Invocation) Int?:
	shown := if inv.output.is_empty(): "program" else: inv.output.clone()

	// The Rust command makes the output's directory and refuses a directory as output.
	if directory(shown): return none
	if shown.contains("/") and not directory(shown.slice(0, shown.last_index_of("/")?)): return none
	if not built_in_c(inv, shown): return none

	stdout().write(f"Built {shown}\n").get()
	return 0

// `ms run`: the program is built into a temporary directory and started with the arguments after `--`; its exit
// status is the command's. None when the Rust command must run.
export fn run_program(inv: Invocation) Int?:
	root := temporary_directory("manuscript-run-")
	if root.is_error(): return none

	dir := root.get().clone()
	executable := f"{dir}/program"

	if not built_in_c(inv, executable):
		void remove(dir, recursive: true)
		return none

	child := spawn(
		executable,
		inv.arguments,
		SpawnOptions(stdin: Stdio.Inherit, stdout: Stdio.Inherit, stderr: Stdio.Inherit),
	)

	var status = 1
	if child.is_ok(): status = child.get().wait().get_or(1)

	void remove(dir, recursive: true)
	return status

// Says on standard error why the C build left the command to the Rust one.
fn trace(error: BuildError) Void:
	match error:
		Failed(message): stderr().write(f"ms build: C build failed: {message}\n").get()
		Unsupported(message): stderr().write(f"ms build: handed to Rust: {message}\n").get()

fn directory(path: String) Bool:
	info := stat(path)
	return info.is_ok() and info.get().is_directory()
