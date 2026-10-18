import {expect_equal, expect_false, expect_not_equal} from "@std/testing.ms"
import {arguments, environment} from "@std/cli.ms"
import {system, endianness, end_of_line, os_type, dev_null} from "@std/system.ms"
import {control, commands, CommandError, CommandOutput} from "@std/process.ms"
import {read_line} from "@std/io.ms"

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

test "process environment is live while CLI environment retains its snapshot":
    let name = "MANUSCRIPT_STDLIB_CONFORMANCE"
    let before = system().environment(name)
    let snapshot = environment().get(name)
    try control().set_environment(name, "stdlib")
    try expect_equal(system().environment(name), some("stdlib"))
    try expect_equal(environment().get(name), snapshot)
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
                "manuscript-nonexistent-command-stdlib",
                [],
                "".to_bytes()
            ) != unavailable
        )
    )

test "managed subprocess streams incrementally and cleans up on scope exit":
    if os_type() == "windows": return

    with child = try commands().spawn("cat", []):
        try child.stdin().write("ping\n".to_bytes())
        let line = try read_line(child.stdout())
        try expect_equal(line.get(""), "ping")
        child.stdin().close()
        try expect_equal((try child.wait()), 0)
        try expect_false((try child.stdout().read()).is_some())
