import {expect_equal, expect_false, expect_not_equal, expect_ok, expect_true} from "@std/testing.ms"
import {arguments, environment} from "@std/cli.ms"
import {system, endianness, end_of_line, os_type, dev_null} from "@std/system.ms"
import {control, commands, CommandError, CommandOutput} from "@std/process.ms"
import {read_line} from "@std/io.ms"

test "CLI test roots have empty arguments and host metadata agrees":
    (arguments().is_empty()) | try expect_true
    let info = system().info()
    (
        (
            info.cpu_count <= 0
            or info.os.byte_length() == 0
            or info.architecture.byte_length() == 0
        )
    ) | try expect_false
    let process = (control().info() | try expect_ok)
    (
        (
            process.pid <= 0
            or process.os != info.os
            or process.architecture != info.architecture
        )
    ) | try expect_false
    system().working_directory() | try expect_equal(
        expected: (control().working_directory() | try expect_ok)
    )
    (endianness() != "LE" and endianness() != "BE") | try expect_false
    (end_of_line() != "\n" and end_of_line() != "\r\n") | try expect_false
    os_type().byte_length() | try expect_not_equal(expected: 0)
    dev_null().byte_length() | try expect_not_equal(expected: 0)

test "process environment is live while CLI environment retains its snapshot":
    let name = "MANUSCRIPT_STDLIB_CONFORMANCE"
    let before = system().environment(name)
    let snapshot = environment().get(name)
    let assigned = (
        control().set_environment(name: name, value: "stdlib") | try expect_ok
    )
    system().environment(name) | try expect_equal(expected: some("stdlib"))
    environment().get(name) | try expect_equal(expected: snapshot)
    (control().environment() | try expect_ok).get(name) | try expect_equal(
        expected: some("stdlib")
    )
    let restored = (
        control().set_environment(name: name, value: before) | try expect_ok
    )

test "subprocess validation returns expected domain errors":
    let invalid: Result[CommandOutput, CommandError] = error(CommandError.InvalidInput)
    commands().run(program: "", arguments: [], input: "".to_bytes()) | try expect_equal(
        expected: invalid
    )
    let unavailable: Result[CommandOutput, CommandError] = error(
        CommandError.Unavailable
    )
    (
        (
            commands().run(
                program: "manuscript-nonexistent-command-stdlib",
                arguments: [],
                input: "".to_bytes()
            ) != unavailable
        )
    ) | try expect_false

test "managed subprocess streams incrementally and cleans up on scope exit":
    if os_type() == "windows": return

    with child = (commands().spawn(program: "cat", arguments: []) | try expect_ok):
        (child.stdin().write("ping\n".to_bytes()) | try expect_ok)
        let line = (read_line(input: child.stdout()) | try expect_ok)
        line.unwrap_or("") | try expect_equal(expected: "ping")
        child.stdin().close()
        child.wait() | try expect_ok | try expect_equal(expected: 0)
        (child.stdout().read() | try expect_ok).is_some() | try expect_false
