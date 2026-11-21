// The frozen conformance corpus against the Rust ms on this host (`make conform`).
// Known failures: tests/conformance/expect-fail.txt plus expect-fail.<os>.txt when
// present. CONFORM_SHARD=i/n splits the run. CONFORM_FAST=1 tests the release `ms`
// that `make build` produced and runs all four phases: the quick local loop.
// CONFORM_LEAKS=1 also checks for leaked heap blocks.
// Arguments after `--` go to `conform-run.ms run`. Usage: ms run tools/conform.ms [--
// extra conform-run.ms run arguments]
import (
	arguments, working_directory from "@std/os/env.ms",
	access, create_directory, read_file, write_file from "@std/os/fs.ms",

	env, exe, host, run_program, tool_ms, use_stats_runtime from "./lib.ms",
)

fn main() Int:
	var code = run_program("cmake", ["-P", "cmake/BuildRuntime.cmake"])
	if code != 0: return code

	// CONFORM_LEAKS=1 links programs against the runtime that counts live heap blocks,
	// and the runner fails a fixture under fuzz/run, e2e or examples that exits with
	// any (the leak sweep).
	if env("CONFORM_LEAKS", "") != "":
		code = use_stats_runtime()
		if code != 0: return code

	create_directory(".artifacts", recursive: true).get()

	allow := ".artifacts/conform-expect-fail.txt"
	var text = (
		read_file("tests/conformance/expect-fail.txt")
		.wait()
		.get()
		.decode_utf8()
		.get_or("")
	)
	host_list := f"tests/conformance/expect-fail.{host()}.txt"
	if access(host_list, 0).is_ok():
		text += read_file(host_list).wait().get().decode_utf8().get_or("")
	write_file(allow, text, replace: true).wait().get()

	// The runner is a Manuscript program, started by `MS` (default target/release/ms).
	// Not the running executable: under `ms run` that is this compiled tool, which
	// would start itself again.
	runner := tool_ms(working_directory().get())

	// The quick loop tests the release-profile compiler `make build` just produced,
	// which also checks faster than the debug one; nothing rebuilds it while the tool
	// runs.
	fast := env("CONFORM_FAST", "") != ""
	ms := if fast: f"target/release/ms{exe()}" else: f"target/debug/ms{exe()}"
	shard := env("CONFORM_SHARD", "0/1")

	// `CONFORM_BACKEND_ONLY=1` is for a run whose lint, check and parse phases another job of the
	// same pull request already ran (the LLVM job beside the Linux legs, or a second
	// pass in the same job).
	skip_frontend := env("CONFORM_BACKEND_ONLY", "") != ""

	if not skip_frontend:
		code = run_program(
			runner.clone(),
			["run", "tools/conform-run.ms", "--", "lint"],
		)
		if code != 0: return code

	extra := arguments()

	// Only `run` and `test` reach the code generator; `check` and `parse` do not depend
	// on it.
	backend_only := skip_frontend
	phases := if backend_only: "run,test" else: "run,check,test"
	main_run := [
		"run",
		"tools/conform-run.ms",
		"--",
		"run",
		"--ms",
		ms.clone(),
		"--phase",
		phases,
		"--exclude-tag",
		"aliasing",
		"--expect-fail",
		allow.clone(),
		"--strict",
		"--shard",
		shard.clone(),
		"--quiet",
		"--markdown",
		".artifacts/conform.md",
	]
	code = run_program(runner.clone(), main_run.concat(extra.clone()))
	if code != 0 or backend_only: return code

	// Parsing and formatting do not depend on aliasing, so the parse phase replays
	// every fixture.
	parse_run := [
		"run",
		"tools/conform-run.ms",
		"--",
		"run",
		"--ms",
		ms.clone(),
		"--phase",
		"parse",
		"--expect-fail",
		allow.clone(),
		"--strict",
		"--shard",
		shard.clone(),
		"--quiet",
		"--markdown",
		".artifacts/conform-parse.md",
	]
	return run_program(runner, parse_run.concat(extra))
