# conform: tags=control-flow,faults,modules,optional,stdlib-io,stdlib-process,stdlib-system,stdlib-testing,testing,tier-io,try-result,scope-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/host.ms
import expect_equal, expect_false, expect_not_equal from "@std/test/test.ms"
import arguments from "@std/os/process.ms"
import endianness, end_of_line, os_type, dev_null, system_info from "@std/os/process.ms"
import CommandError, CommandOutput, Stdio, run, spawn, environment, process_info, set_environment from "@std/os/process.ms"
import read_line from "@std/io/io.ms"

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
    let invalid: CommandOutput!CommandError = error(CommandError.InvalidInput)
    try expect_equal(run("", [], "".to_bytes()), invalid)

    let unavailable: CommandOutput!CommandError = error(
        CommandError.Unavailable
    )
    try expect_false(
        (
            run(
                "manuscript-nonexistent-command-stdlib", [], "".to_bytes()
            ) != unavailable
        )
    )

test "subprocess streams that are not piped are closed":
    if os_type() == "windows": return

    let child = try spawn(
        "sh", ["-c", "cat; echo done >&2"], stdin: Stdio.Null, stdout: Stdio.Null
    )
    try expect_equal((try child.wait()), 0)

    let line = try read_line(child.stderr())
    try expect_equal(line.get(""), "done")
    try expect_false(child.stdout().read().is_ok())
    try expect_false(child.stdin().write("x").is_ok())

test "managed subprocess streams incrementally and cleans up on scope exit":
    if os_type() == "windows": return

    let child = try spawn("cat", [])
    try child.stdin().write("ping\n")

    let line = try read_line(child.stdout())
    try expect_equal(line.get(""), "ping")
    child.stdin().close()
    try expect_equal((try child.wait()), 0)
    try expect_false((try child.stdout().read()).is_some())
