import Bytes from "@std/bytes.ms"
import (CommandOutput, Commands, Stdio, Subprocess) from "@std/os/process.ms"
import Duration from "@std/os/time.ms"

# Shifts the node ids below so that `Echo.run` has the id of a method in another module
# (`second.ms` or the standard library): defaults must be found by module and id.
export fn padding() Int:
    var total = 0
    total += 0
    total += 1
    total += 2
    total += 3
    total += 4
    return total

export type Echo:
    code: Int

impl Commands for Echo:
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Int?,
        timeout: Duration?,
        cwd: String?,
        env: Map[String, String]
    ) CommandOutput!:
        return ok(CommandOutput(self.code, input, "".to_bytes(), 0))

    fn spawn(
        program: String,
        arguments: List[String],
        stdin: Stdio,
        stdout: Stdio,
        stderr: Stdio,
        cwd: String?,
        env: Map[String, String]
    ) Subprocess!:
        return error(
            Error(
                "process: service unavailable", kind: ErrorCategory.Unavailable
            )
        )
