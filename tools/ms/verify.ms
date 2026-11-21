// `ms verify [--json] [--no-test] [--deny-warnings] [target]`: check, fmt --check, lint and
// test on one target in one result. Orchestration only: each step is this command line
// run as a child with its streams captured.
import (
	Matches from "@std/cli/command.ms",
	JsonValue, parse from "@std/data/json.ms",
	stderr, stdout from "@std/io/io.ms",
	RunOptions, process_info, run from "@std/os/process.ms",
	expect_equal from "@std/test/test.ms",
	monotonic from "@std/time.ms",

	resolve_input from "./args.ms",
	flag, list_of, number, object, render_document, text, with from "./json_out.ms",
)

// Findings printed per failed step in text mode (`--json` carries every one).
FINDING_LIMIT := 8

type Step:
	name: String
	status: String
	exit_code: Int = 0
	duration_ns: Int = 0
	reason: String = ""
	error: String = ""
	result: JsonValue? = none

fn say(message: String) Void:
	stdout().write(message).get()

fn complain(message: String) Void:
	stderr().write(message + "\n").get()

fn Step.to_json() JsonValue:
	var out = object()
	out = with(out, "name", text(self.name))
	out = with(out, "status", text(self.status))
	out = with(out, "exit_code", number(self.exit_code))
	out = with(out, "duration_ns", number(self.duration_ns))
	if not self.reason.is_empty(): out = with(out, "reason", text(self.reason))
	if not self.error.is_empty(): out = with(out, "error", text(self.error))
	if result := self.result: out = with(out, "result", result.clone())
	return out

fn skipped(name: String, reason: String) Step:
	return Step(name: name, status: "skipped", reason: reason)

// Runs this command line with `args`, capturing its streams.
fn run_step(name: String, args: List[String]) Step:
	started := monotonic()
	info := process_info()
	var step = Step(name: name, status: "failed")

	if info.is_error():
		step.error = info.err().message.clone()
		return step

	finished := run(info.get().executable.clone(), args.clone(), RunOptions()).wait()
	step.duration_ns = monotonic().difference(started).to_nanoseconds()

	if finished.is_error():
		step.error = finished.err().message.clone()
		return step

	output := finished.get()
	step.exit_code = output.exit_code

	printed := output.stdout.decode_utf8().get_or("").trim()
	parsed := parse(printed)
	if parsed.is_ok(): step.result = parsed.get()

	if output.exit_code == 0:
		step.status = "passed"
		return step

	if step.result.is_none():
		step.error = output.stderr.decode_utf8().get_or("").trim()
	return step

fn member_text(value: JsonValue, key: String) String:
	if member := value.get(key): return member.as_string().get_or("")
	return ""

fn position_number(position: JsonValue, key: String) String:
	if member := position.get(key): return member.as_int().get_or(0).to_string()
	return "0"

// The leading findings of a step, so the text summary names the problem instead of only
// pointing at another command.
fn findings_of(step: Step) List[String]:
	var found = List[String]()
	if not step.error.is_empty(): found.append(step.error.clone())

	result := step.result
	if result.is_none(): return found

	document := result.get()

	if diagnostics := document.get("diagnostics"):
		// Errors first: a capped list must not bury them under warnings.
		var ordered = List[JsonValue]()

		for pass in 0..2:
			for item in diagnostics.as_list().get_or([]):
				is_error := member_text(item, "severity") == "error"
				if (pass == 0) == is_error: ordered.append(item.clone())

		for item in ordered:
			var file = ""
			var line = "0"
			var column = "0"

			if position := item.get("position"):
				file = member_text(position, "file")
				line = position_number(position, "line")
				column = position_number(position, "column")

			found.append(f"{file}:{line}:{column}: {member_text(item, "message")}")

	if tests := document.get("tests"):
		for item in tests.as_list().get_or([]):
			if member_text(item, "status") == "failed":
				failure := member_text(item, "failure").split("\n")[0].clone()
				found.append(f"{member_text(item, "name")}: {failure}")

	return found

fn print_findings(step: Step) Int:
	found := findings_of(step)
	var shown = 0

	for finding in found:
		if shown == FINDING_LIMIT:
			complain(f"  ... {found.length() - shown} more")
			break

		complain(f"  {finding}")
		shown += 1

	return found.length()

export fn run_verify(m: Matches) Int:
	structured := m.bool("json")
	skip_test := m.bool("no-test")
	deny_warnings := m.bool("deny-warnings")
	given := m.string("target")

	if given.is_empty():
		complain(
			"ms verify: the target is empty; pass a .ms file, directory, or ms.toml"
		)
		return 2

	resolved := resolve_input("verify", given)

	if resolved.is_error():
		complain(resolved.err().message)
		return 2

	target := resolved.get()

	// Subcommands parse options again; retain the target's positional meaning.
	input := if target.starts_with("-"): f"./{target}" else: target.clone()
	var steps = List[Step]()
	var passed = true
	check := run_step("check", ["check", input.clone(), "--json"])
	check_passed := check.status == "passed"
	steps.append(check)
	steps.append(run_step("fmt", ["fmt", input.clone(), "--check", "--json"]))

	if check_passed:
		var lint_args = ["lint", input.clone(), "--json"]
		if deny_warnings: lint_args.append("--deny-warnings")
		steps.append(run_step("lint", lint_args))
	else:
		steps.append(skipped("lint", "check failed"))

	if skip_test:
		steps.append(skipped("test", "--no-test"))
	else if not check_passed:
		steps.append(skipped("test", "check failed"))
	else:
		steps.append(run_step("test", ["test", input.clone(), "--json"]))

	for step in steps:
		if step.status == "failed": passed = false
		if not structured: say(f"{step.name.pad_end(6, " ")} {step.status}\n")

	status := if passed: 0 else: 1

	if structured:
		var document = object()
		document = with(document, "format", number(1))
		document = with(document, "target", text(target))
		document = with(document, "ok", flag(passed))
		document = with(document, "steps", list_of(steps.map(fn step: step.to_json())))
		say(render_document(document))
		return status

	for step in steps:
		if step.name == "lint" and step.status == "passed":
			if print_findings(step) > 0:
				complain(
					"lint warnings do not fail verify; pass --deny-warnings to fail on them"
				)

	for step in steps:
		if step.status != "failed": continue

		print_findings(step)
		complain(
			f"{step.name} failed; run ms {step.name} {target} for details (or ms verify {target} --json for every step)"
		)

	return status

test "findings list errors before warnings and failed tests by name":
	document := parse(
		"{\"diagnostics\":[{\"severity\":\"warning\",\"message\":\"w\",\"position\":{\"file\":\"a.ms\",\"line\":1,\"column\":2}},{\"severity\":\"error\",\"message\":\"e\",\"position\":{\"file\":\"b.ms\",\"line\":3,\"column\":4}}],\"tests\":[{\"status\":\"failed\",\"name\":\"t\",\"failure\":\"boom\\nmore\"}]}"
	)?
	step := Step(name: "check", status: "failed", result: document)
	expect_equal(findings_of(step), ["b.ms:3:4: e", "a.ms:1:2: w", "t: boom"])?
