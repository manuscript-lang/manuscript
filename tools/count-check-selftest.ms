// The ownership-count gate must fail when its fixture fails, even when cleanup is
// complete (`make count-check`, after the gate itself). It runs tools/count-check.ms on
// the fixtures in tools/count-check-selftest. MS names the ms that runs the gate
// (default target/release/ms). Usage: ms run tools/count-check-selftest.ms
import (
	stdout from "@std/io/io.ms",
	working_directory from "@std/os/env.ms",
	RunOptions, run from "@std/os/process.ms",

	note, tool_ms from "./lib.ms",
)

// The exit status and combined output of the gate on `fixture`, run by `compiler`.
type Gate:
	code: Int
	output: String

fn gate(root: String, compiler: String, fixture: String) Gate:
	var settings = Map[String, String]()
	settings["MS"] = compiler.clone()

	arguments := [
		"run", "{root}/tools/count-check.ms", "--build-type", "Debug", "--",
		"tools/count-check-selftest/{fixture}"
	]

	if out := run(
		tool_ms(root.clone()),
		arguments,
		RunOptions(cwd: root.clone(), env: settings),
	).wait():
		text := out.stdout.decode_utf8().get("") + out.stderr.decode_utf8().get("")
		return Gate(out.exit_code, text)

	return Gate(125, "cannot start the gate\n")

fn expect(var failures: List[String], what: String, held: Bool, shown: Gate) Unit:
	if not held: failures.append("{what}\n{shown.output}")

fn main() Int:
	root := working_directory().get()
	compiler := tool_ms(root.clone())
	var failures = List[String]()
	failed := gate(root.clone(), compiler.clone(), "nonzero.ms")
	expect(var failures, "a failing child must fail the gate", failed.code == 1, failed)
	for profile in ["debug", "release"]:
		expect(
			var failures,
			"the {profile} run must report its exit status",
			failed.output.contains("({profile}) exited 7"),
			failed,
		)

	// The runtime is the real entry+stats one: complete cleanup must not hide the
	// failure.
	expect(
		var failures,
		"the failure must hold with zero live blocks",
		failed.output.contains("ms-rt live blocks at exit: 0"),
		failed,
	)

	passed := gate(root.clone(), compiler.clone(), "success.ms")
	expect(var failures, "a clean fixture must pass", passed.code == 0, passed)
	expect(
		var failures,
		"the gate must count its expectations",
		passed.output.contains("checked 2 expectations, 0 failing"),
		passed,
	)

	rejected := gate(root.clone(), compiler.clone(), "rejected.ms")
	expect(var failures, "a rejected fixture must fail", rejected.code == 1, rejected)
	expect(
		var failures,
		"a rejected fixture reports its failed build, not a leak",
		rejected.output.contains("exited 1") and rejected.output.contains(
			"type:"
		) and not rejected.output.contains("leak:"),
		rejected,
	)

	unavailable := gate(root.clone(), "{root}/target/missing-ms", "success.ms")
	expect(
		var failures,
		"a missing compiler must fail without a leak report",
		unavailable.code == 1 and unavailable.output.contains(
			"could not run"
		) and not unavailable.output.contains("leak:"),
		unavailable,
	)
	for message in failures: note("FAIL {message}")
	if not failures.is_empty(): return 1

	stdout().write("count-check-selftest: 4 cases passed\n").get()
	return 0
