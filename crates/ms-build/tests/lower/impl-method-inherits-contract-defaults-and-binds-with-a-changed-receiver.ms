# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "msrt_string_to_bytes"

import {Subprocess, CommandOutput, CommandError} from "@std/process.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import CsvOptions from "@std/csv.ms"

interface Runner:
    var fn run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) Result[CommandOutput, CommandError]
    fn spawn(program: String, arguments: List[String]) Result[Subprocess, CommandError]

type Capture:
    calls: Int

impl Runner for Capture:
    var fn run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Optional[Int],
        timeout: Optional[Duration]
    ) Result[CommandOutput, CommandError]:
        self.calls += 1
        return ok(CommandOutput(0, input, "".to_bytes()))

    fn spawn(program: String, arguments: List[String]) Result[Subprocess, CommandError]:
        return error(CommandError.Unavailable)

export fn main() Int:
    var capture = Capture(0)
    let _bound = capture.run
    let _r = capture.run("x", [], "".to_bytes())
    let _o = CsvOptions()
    return 0
