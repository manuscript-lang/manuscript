// The frozen conformance corpus against the Rust ms on this host (`make conform`).
// Known failures: tests/conformance/expect-fail.txt plus expect-fail.<os>.txt when
// present. CONFORM_SHARD=i/n splits the run. CONFORM_FAST=1 builds every program with Cranelift (the
// Debug backend, about 3x faster than LLVM) and still runs all four phases: the quick local loop. CONFORM_LEAKS=1 also checks for leaked
// heap blocks. Arguments after `--` go to `ms-conform run`. Usage: ms run
// tools/conform.ms [-- extra ms-conform run arguments]
import (
	arguments from "@std/os/env.ms",
	access, create_directory, read_file, write_file from "@std/os/fs.ms",

	env, exe, host, run_program, use_stats_runtime from "./lib.ms",
)

fn main() Int:
	var code = run_program("cargo", ["xtask", "runtime"])
	if code != 0: return code

	// Only the runner is built here: this tool runs on `target/debug/ms`, and Windows
	// cannot replace an executable that is running (`make conform` and CI build
	// `ms-cli` before they start the tool).
	code = run_program(
		"cargo",
		[
			"build", "--locked", "-q", "-p", "ms-conform", "--target-dir", "target"
		],
	)
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
		.get("")
	)
	host_list := "tests/conformance/expect-fail.{host()}.txt"
	if access(host_list, 0).is_ok():
		text += read_file(host_list).wait().get().decode_utf8().get("")
	write_file(allow, text, replace: true).wait().get()

	conform := "target/debug/ms-conform{exe()}"
	// The quick loop tests the release-profile compiler `make build` just produced, which also checks
	// faster than the debug one; nothing rebuilds it while the tool runs.
	fast := env("CONFORM_FAST", "") != ""
	ms := if fast: "target/release/ms{exe()}" else: "target/debug/ms{exe()}"
	shard := env("CONFORM_SHARD", "0/1")
	code = run_program(conform, ["lint"])
	if code != 0: return code

	extra := arguments()

	// Only `run` and `test` reach a code generator, so a second pass with
	// `MS_BACKEND=cranelift` skips the check and parse phases: the LLVM pass already
	// ran them, and their results do not depend on the backend.
	backend_only := env("MS_BACKEND", "") == "cranelift" and not fast
	phases := if backend_only: "run,test" else: "run,check,test"
	main_run := [
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
	code = run_program(conform, main_run.concat(extra.clone()))
	if code != 0 or backend_only: return code

	// Parsing and formatting do not depend on aliasing, so the parse phase replays
	// every fixture.
	parse_run := [
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
	return run_program(conform, parse_run.concat(extra))
