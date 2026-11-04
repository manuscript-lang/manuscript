import expect_equal, expect_false, expect_not_equal from "@std/test/test.ms"
import arguments from "@std/os/process.ms"
import endianness, end_of_line, os_type, dev_null, system_info from "@std/os/process.ms"
import (
    CommandOutput,
    Stdio,
    run,
    spawn,
    environment,
    process_info,
    set_environment
) from "@std/os/process.ms"
import lines from "@std/io/streams.ms"

test "CLI test roots have empty arguments and host metadata agrees":
    try expect_false(not arguments().is_empty())

    let info = system_info()
    try expect_false(
        (
            info.cpu_count <= 0
            or info.os.byte_length() == 0
            or info.architecture.byte_length() == 0
        )
    )

    let process = try process_info()
    try expect_false(
        (
            process.pid <= 0
            or process.os != info.os
            or process.architecture != info.architecture
        )
    )
    try expect_false(endianness() != "LE" and endianness() != "BE")
    try expect_false(end_of_line() != "\n" and end_of_line() != "\r\n")
    try expect_not_equal(os_type().byte_length(), 0)
    try expect_not_equal(dev_null().byte_length(), 0)

test "process environment reflects live changes":
    let name = "MANUSCRIPT_STDLIB_CONFORMANCE"
    let before = (try environment()).get(name)
    try set_environment(name, "stdlib")
    try expect_equal((try environment()).get(name), "stdlib")
    try set_environment(name, before)

test "subprocess validation returns expected domain errors":
    let invalid: CommandOutput! = error(
        Error("process: invalid input", kind: "EINVAL")
    )
    try expect_equal(run("", [], "".to_bytes()).wait(), invalid)

    let missing = run("manuscript-nonexistent-command-stdlib", [], "".to_bytes()).wait()
    try expect_equal(missing.err().kind, "EAGAIN")
    try expect_equal(
        missing.err().message,
        "process: service unavailable: manuscript-nonexistent-command-stdlib"
    )

test "subprocess streams that are not piped are closed":
    if os_type() == "windows": return

    let child = try spawn(
        "sh", ["-c", "cat; echo done >&2"], stdin: Stdio.Null, stdout: Stdio.Null
    )
    try expect_equal((try child.wait()), 0)

    var errors = lines(child.stderr())
    let line = try errors.read().wait()
    try expect_equal(line.get(""), "done")

    var silent = child.stdout()
    try expect_false((try silent.read().wait()).is_some())

    var input = child.stdin()
    try expect_false(input.write("x".to_bytes()).is_ok())

test "managed subprocess streams incrementally and cleans up on scope exit":
    if os_type() == "windows": return

    let child = try spawn("cat", [])
    var input = child.stdin()
    try input.write("ping\n".to_bytes())
    try input.flush().wait()

    var output = lines(child.stdout())
    let line = try output.read().wait()
    try expect_equal(line.get(""), "ping")
    try input.close()
    try expect_equal((try child.wait()), 0)
    try expect_false((try output.read().wait()).is_some())

test "run and spawn pass the environment to the child":
    if os_type() == "windows": return

    var env: Map[String, String] = Map[String, String]()
    env.add("MS_CHILD_VALUE", "from-parent")

    let output = try run(
        "sh", ["-c", "printf %s \"$MS_CHILD_VALUE\""], "".to_bytes(), env: env.clone()
    ).wait()
    try expect_equal(output.stdout, "from-parent".to_bytes())

    let child = try spawn(
        "sh", ["-c", "printf %s \"$MS_CHILD_VALUE\" >&2"], stdin: Stdio.Null,
        stdout: Stdio.Null, env: env
    )
    try expect_equal((try child.wait()), 0)

    var errors = child.stderr()
    let text = try errors.read().wait()
    try expect_equal(text.get("".to_bytes()), "from-parent".to_bytes())
