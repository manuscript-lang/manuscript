// `ms check FILE.ms [--json]` over libms (`ms_tool_check`, compiler/include/ms/tool.h). The C checker answers when it
// covers every function and declaration of the file and its project modules; for anything else (several targets, a
// directory, `--fix`, `--watch`, a diagnostic it cannot place exactly) `run_check` returns none and the caller runs
// the Rust command. `compiler/tests/check-cmd-diff.sh` holds the C answer to the Rust output on the corpus.
import stderr, stdout from "@std/io/io.ms"

import Invocation from "./args.ms"

// Status 1 is an error in the call; status 2 is a request the C checker does not cover.
export enum CheckError:
	Failed(message: String)
	Unsupported(message: String)

// The standard output, the standard error and the exit status (as text) of `ms check`.
extern fn ms_tool_check(target: String, json: Bool) List[String]!CheckError

// The exit status, or none when the Rust command must run.
export fn run_check(inv: Invocation) Int?:
	if inv.watch or inv.fix or inv.with_text or inv.each or inv.deny_warnings: return none
	if inv.targets.length() != 1: return none

	target := inv.targets[0].clone()
	if not target.ends_with(".ms"): return none

	got := ms_tool_check(target, inv.structured)
	if got.is_error(): return none

	rows := got.get()
	stdout().write(rows[0].clone()).get()
	stderr().write(rows[1].clone()).get()
	return rows[2].parse_int().get()
