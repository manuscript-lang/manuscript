import {arguments, environment} from "@std/cli.ms"
import {system, endianness, end_of_line, os_type, dev_null} from "@std/system.ms"
import {control, commands, CommandError, CommandOutput} from "@std/process.ms"
import {read_line} from "@std/io.ms"
import panic from "@std/faults.ms"

test "CLI test roots have empty arguments and host metadata agrees":
    if not arguments().is_empty(): return panic("test arguments")

    let info = system().info()
    if (
        info.cpu_count <= 0
        or info.os.byte_length() == 0
        or info.architecture.byte_length() == 0
    ): return panic("system info")

    let process = try control().info()
    if (
        process.pid <= 0
        or process.os != info.os
        or process.architecture != info.architecture
    ): return panic("process info")
    if system().working_directory() != (try control().working_directory()): return panic(
        "working directory"
    )
    if endianness() != "LE" and endianness() != "BE": return panic("endianness")
    if end_of_line() != "\n" and end_of_line() != "\r\n": return panic("line ending")
    if os_type().byte_length() == 0: return panic("os type")
    if dev_null().byte_length() == 0: return panic("null device")

test "process environment is live while CLI environment retains its snapshot":
    let name = "MANUSCRIPT_STDLIB_CONFORMANCE"
    let before = system().environment(name)
    let snapshot = environment().get(name)
    try control().set_environment(name, value: "stdlib")
    if system().environment(name) != some("stdlib"): return panic("system environment")
    if environment().get(name) != snapshot: return panic(
        "CLI environment snapshot changed"
    )
    if (try control().environment()).get(name) != some("stdlib"): return panic(
        "process environment"
    )

    try control().set_environment(name, value: before)

test "subprocess validation returns expected domain errors":
    let invalid: Result[CommandOutput, CommandError] = error(CommandError.InvalidInput)
    if commands().run(program: "", arguments: [], input: "".to_bytes()) != invalid: return panic(
        "empty program"
    )

    let unavailable: Result[CommandOutput, CommandError] = error(
        CommandError.Unavailable
    )
    if (
        commands().run(
            program: "manuscript-nonexistent-command-stdlib",
            arguments: [],
            input: "".to_bytes()
        ) != unavailable
    ): return panic("missing command")

test "managed subprocess streams incrementally and cleans up on scope exit":
    if os_type() == "windows": return

    with child = try commands().spawn(program: "cat", arguments: []):
        try child.stdin().write("ping\n".to_bytes())
        let line = try read_line(input: child.stdout())
        if line.unwrap_or("") != "ping": return panic("echo")

        child.stdin().close()
        if (try child.wait()) != 0: return panic("exit status")
        if (try child.stdout().read()).is_some(): return panic("stdout eof")
