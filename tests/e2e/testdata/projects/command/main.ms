import panic from "@std/faults.ms"

import Process from "@std/cli.ms"
import List from "@std/collections.ms"

export fn main(process: Process) -> Int:
    match process.commands.run(program: "/bin/printf", arguments: ["hello"], input: "".to_bytes(), max_output_bytes: 64, timeout: 1.seconds):
        error(_):
            return 1
        ok(output):
            if not (output.exit_code == 0):
                return panic(message: "check failed")
            process.stdout.write(data: output.stdout)
            return 0
