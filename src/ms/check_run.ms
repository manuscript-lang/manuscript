// `ms check FILE.ms... [--json [--with-text [--each]]]` over libms (`ms_tool_check`,
// src/compiler/include/ms/tool.h). The C checker answers when it covers every function
// and declaration of the file and its project modules; for anything else (a directory,
// `--fix`, `--watch`, `--deny-warnings`, a diagnostic it cannot place exactly)
// `run_check` returns none and the caller runs the Rust command.
// `src/compiler/tests/check-cmd-diff.sh` holds the C answer to the Rust output on the
// corpus.
import (
	stderr, stdout from "@std/io/io.ms",
	environment from "@std/os/env.ms",

	Invocation from "./args.ms",
)

// Status 1 is an error in the call; status 2 is a request the C checker does not cover.
export enum CheckError:
	Failed(message: String)
	Unsupported(message: String)

// The standard output, the standard error and the exit status (as text) of `ms check`
// over one target, or over several with `each`.
extern fn ms_tool_check(
	targets: List[String],
	json: Bool,
	with_text: Bool,
	each: Bool,
) List[String]!CheckError

// The standard output, the standard error and the exit status (as text) of `ms check
// TARGET`; none when the C checker does not cover it.
export fn check_rows(target: String, json: Bool) List[String]?:
	got := ms_tool_check([target], json, false, false)
	if got.is_error(): return none

	return got.get()

// Says on standard error why the C checker left the command to the Rust one.
fn trace(error: CheckError) Void:
	match error:
		Failed(message): stderr().write(f"ms check: C check failed: {message}\n").get()
		Unsupported(message): stderr().write(
			f"ms check: handed to Rust: {message}\n"
		).get()

// The exit status, or none when the Rust command must run.
export fn run_check(inv: Invocation) Int?:
	if inv.watch or inv.fix or inv.deny_warnings: return none
	if inv.targets.is_empty(): return none
	if inv.targets.length() != 1 and not inv.each: return none
	if inv.targets.any(fn target: not target.ends_with(".ms")): return none

	got := ms_tool_check(inv.targets.clone(), inv.structured, inv.with_text, inv.each)

	if got.is_error():
		vars := environment()
		if vars.is_ok() and vars.get().contains("MS_DRIVER_TRACE"): trace(got.err())
		return none

	rows := got.get()
	stdout().write(rows[0].clone()).get()
	stderr().write(rows[1].clone()).get()
	return rows[2].parse_int().get()
