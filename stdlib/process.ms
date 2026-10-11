# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import List from "@std/collections.ms"
import Result from "@std/result.ms"

export type CommandError:
    case InvalidInput
    case Unavailable
    case TimedOut
    case OutputLimit
    case Failed(message: String)

export type CommandOutput:
    exit_code: Int
    stdout: Bytes
    stderr: Bytes

export interface Commands:
    fn run(program: String, arguments: List[String], input: Bytes, max_output_bytes: Int, timeout: Duration) -> Result[CommandOutput, CommandError]
