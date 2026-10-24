# conform: tags=control-flow,faults,formatter,modules,optional,parser,stdlib-io,stdlib-process,stdlib-system,stdlib-testing,testing,tier-io,try-result,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/host.ms
from "@std/testing.ms" import expect_equal, expect_false, expect_not_equal
from "@std/process.ms" import arguments
from "@std/process.ms" import system, endianness, end_of_line, os_type, dev_null
from "@std/process.ms" import control, commands, CommandError, CommandOutput, Stdio
from "@std/io.ms" import read_line

test "CLI test roots have empty arguments and host metadata agrees":
    try expect_false(not arguments().is_empty())

    let info = system().info()
    try expect_false(
        (
            info.cpu_count <= 0
            or info.os.byte_length() == 0
            or info.architecture.byte_length() == 0
        )
    )

    let process = try control().info()
    try expect_false(
        (
            process.pid <= 0
            or process.os != info.os
            or process.architecture != info.architecture
        )
    )
    try expect_equal(system().working_directory(), (try control().working_directory()))
    try expect_false(endianness() != "LE" and endianness() != "BE")
    try expect_false(end_of_line() != "\n" and end_of_line() != "\r\n")
    try expect_not_equal(os_type().byte_length(), 0)
    try expect_not_equal(dev_null().byte_length(), 0)

test "process environment reflects live changes":
    let name = "MANUSCRIPT_STDLIB_CONFORMANCE"
    let before = (try control().environment()).get(name)
    try control().set_environment(name, "stdlib")
    try expect_equal((try control().environment()).get(name), some("stdlib"))
    try control().set_environment(name, before)

test "subprocess validation returns expected domain errors":
    let invalid: Result[CommandOutput, CommandError] = error(CommandError.InvalidInput)
    try expect_equal(commands().run("", [], "".to_bytes()), invalid)

    let unavailable: Result[CommandOutput, CommandError] = error(
        CommandError.Unavailable
    )
    try expect_false(
        (
            commands().run(
                "manuscript-nonexistent-command-stdlib", [], "".to_bytes()
            ) != unavailable
        )
    )

test "subprocess streams that are not piped are closed":
    if os_type() == "windows": return

    with try commands().spawn(
        "sh", ["-c", "cat; echo done >&2"], stdin: Stdio.Null, stdout: Stdio.Null
    ) as child:
        try expect_equal((try child.wait()), 0)

        let line = try read_line(child.stderr())
        try expect_equal(line.get(""), "done")
        try expect_false(child.stdout().read().is_ok())
        try expect_false(child.stdin().write("x").is_ok())

test "managed subprocess streams incrementally and cleans up on scope exit":
    if os_type() == "windows": return

    with try commands().spawn("cat", []) as child:
        try child.stdin().write("ping\n")

        let line = try read_line(child.stdout())
        try expect_equal(line.get(""), "ping")
        child.stdin().close()
        try expect_equal((try child.wait()), 0)
        try expect_false((try child.stdout().read()).is_some())
