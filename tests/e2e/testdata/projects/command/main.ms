import commands from "@std/process.ms"
import stdout from "@std/io.ms"
import panic from "@std/faults.ms"

export fn main() -> Int:
    let ran = commands().run(
        program: "/bin/printf",
        arguments: ["hello"],
        input: "".to_bytes(),
        max_output_bytes: 64,
        timeout: 1.seconds
    )
    if ran.is_error(): return 1

    let output = ran.unwrap()
    if not (output.exit_code == 0):
        return panic(message: "check failed")

    stdout().write(data: output.stdout)
    return 0
