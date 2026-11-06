import Bytes from "@std/bytes.ms"
import (
    CommandOutput,
    Commands,
    RunOptions,
    SpawnOptions,
    Subprocess
) from "@std/os/process.ms"

export type Quiet:
    code: Int

impl Commands for Quiet:
    fn run(program: String, arguments: List[String], options: RunOptions) CommandOutput!:
        return ok(CommandOutput(self.code, options.input.clone(), "".to_bytes(), 0))

    fn spawn(
        program: String,
        arguments: List[String],
        options: SpawnOptions
    ) Subprocess!:
        return error(Error("process: service unavailable", kind: "EAGAIN"))
