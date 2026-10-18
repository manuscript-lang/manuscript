import commands from "@std/process.ms"
import stdout from "@std/io.ms"
import panic from "@std/faults.ms"

export fn main() Int:
    if let output = commands().run(
        program: "/bin/printf",
        arguments: ["hello"],
        input: "".to_bytes(),
        max_output_bytes: 64,
        timeout: 1.seconds
    ):
        if not (output.exit_code == 0):
            return panic(message: "check failed")
        if stdout().write(data: output.stdout).is_error():
            return 1

        return 0
    else:
        return 1
