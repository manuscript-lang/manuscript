import Bytes from "@std/bytes.ms"
import (
    CommandError,
    CommandOutput,
    Commands,
    Stdio,
    Subprocess
) from "@std/os/process.ms"
import Duration from "@std/os/time.ms"

export type Quiet:
    code: Int

impl Commands for Quiet:
    fn run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Int?,
        timeout: Duration?,
        cwd: String?,
        env: Map[String, String]
    ) CommandOutput!CommandError:
        return ok(CommandOutput(self.code, input, "".to_bytes(), 0))

    fn spawn(
        program: String,
        arguments: List[String],
        stdin: Stdio,
        stdout: Stdio,
        stderr: Stdio,
        cwd: String?,
        env: Map[String, String]
    ) Subprocess!CommandError:
        return error(CommandError.Unavailable)
