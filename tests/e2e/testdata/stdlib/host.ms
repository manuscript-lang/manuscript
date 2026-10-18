import arguments from "@std/process.ms"
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

test "process environment reflects live changes":
    let name = "MANUSCRIPT_STDLIB_CONFORMANCE"
    let before = (try control().environment()).get(name)
    try control().set_environment(name, "stdlib")
    if (try control().environment()).get(name) != some("stdlib"): return panic(
        "process environment"
    )

    try control().set_environment(name, before)

test "subprocess validation returns expected domain errors":
    let invalid: Result[CommandOutput, CommandError] = error(CommandError.InvalidInput)
    if commands().run("", [], "".to_bytes()) != invalid: return panic("empty program")

    let unavailable: Result[CommandOutput, CommandError] = error(
        CommandError.Unavailable
    )
    if (
        commands().run(
            "manuscript-nonexistent-command-stdlib",
            [],
            "".to_bytes()
        ) != unavailable
    ): return panic("missing command")

test "managed subprocess streams incrementally and cleans up on scope exit":
    if os_type() == "windows": return

    with child = try commands().spawn("cat", []):
        try child.stdin().write("ping\n".to_bytes())
        let line = try read_line(child.stdout())
        if line.get("") != "ping": return panic("echo")

        child.stdin().close()
        if (try child.wait()) != 0: return panic("exit status")
        if (try child.stdout().read()).is_some(): return panic("stdout eof")
