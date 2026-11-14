// conform: tags=testing,tier-io
// conform: phase=test
import (
	lines from "@std/io/streams.ms",
	arguments, environment, set_environment from "@std/os/env.ms",
	CommandOutput,
	RunOptions,
	SpawnOptions,
	Stdio,
	process_info,
	run,
	spawn from "@std/os/process.ms",
	Endianness,
	Os,
	dev_null,
	end_of_line,
	endianness,
	os,
	system_info from "@std/os/system.ms",
	expect_equal, expect_false, expect_not_equal, expect_true from "@std/test/test.ms",
)

test "CLI test roots have empty arguments and host metadata agrees":
	expect_false(not arguments().is_empty())?

	info := system_info()
	expect_false(
		(
			info.cpu_count <= 0
			or info.os.byte_length() == 0
			or info.architecture.byte_length() == 0
		)
	)?

	process := process_info()?
	expect_false(
		(
			process.pid <= 0
			or process.os != info.os
			or process.architecture != info.architecture
		)
	)?
	expect_true(endianness() == Endianness.Little or endianness() == Endianness.Big)?
	expect_false(end_of_line() != "\n" and end_of_line() != "\r\n")?
	expect_not_equal(os(), Os.Other)?
	expect_not_equal(dev_null().byte_length(), 0)?

test "process environment reflects live changes":
	name := "MANUSCRIPT_STDLIB_CONFORMANCE"
	before := (environment()?).get(name)
	set_environment(name, "stdlib")?
	expect_equal((environment()?).get(name), "stdlib")?
	set_environment(name, before)?

test "subprocess validation returns expected domain errors":
	invalid: CommandOutput! := error(Error("process: invalid input", kind: "EINVAL"))
	expect_equal(run("", [], RunOptions(input: "".to_bytes())).wait(), invalid)?

	missing := run(
		"manuscript-nonexistent-command-stdlib",
		[],
		RunOptions(input: "".to_bytes()),
	).wait()
	expect_equal(missing.err().kind, "ENOENT")?
	expect_equal(
		missing.err().message,
		"process: not found: manuscript-nonexistent-command-stdlib",
	)?

test "subprocess streams that are not piped are closed":
	child := spawn(
		"sh",
		["-c", "cat; echo done >&2"],
		SpawnOptions(stdin: Stdio.Null, stdout: Stdio.Null),
	)?
	expect_equal((child.wait()?), 0)?

	var errors = lines(child.stderr())
	line := errors.next()?
	expect_equal(line.get(""), "done")?

	var silent = child.stdout()
	expect_false((silent.next()?).is_some())?

	var input = child.stdin()
	expect_false(input.write("x".to_bytes()).is_ok())?

test "managed subprocess streams incrementally and cleans up on scope exit":
	child := spawn("cat", [])?
	var input = child.stdin()
	input.write("ping\n".to_bytes())?
	input.flush()?

	var output = lines(child.stdout())
	line := output.next()?
	expect_equal(line.get(""), "ping")?
	input.close()?
	expect_equal((child.wait()?), 0)?
	expect_false((output.next()?).is_some())?

test "run and spawn pass the environment to the child":
	var env: Map[String, String] = Map[String, String]()
	env.add("MS_CHILD_VALUE", "from-parent")

	output := run(
		"sh",
		["-c", "printf %s \"$MS_CHILD_VALUE\""],
		RunOptions(input: "".to_bytes(), env: env.clone()),
	).wait()?
	expect_equal(output.stdout, "from-parent".to_bytes())?

	child := spawn(
		"sh",
		["-c", "printf %s \"$MS_CHILD_VALUE\" >&2"],
		SpawnOptions(stdin: Stdio.Null, stdout: Stdio.Null, env: env),
	)?
	expect_equal((child.wait()?), 0)?

	var errors = child.stderr()
	text := errors.next()?
	expect_equal(text.get("".to_bytes()), "from-parent".to_bytes())?
