# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "msrt_string_to_bytes"

import Subprocess, CommandOutput from "@std/os/process.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/os/time.ms"
import CsvOptions from "@std/data/csv.ms"

interface Runner:
    var fn run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Int?,
        timeout: Duration?
    ) Result[CommandOutput, Error]
    fn spawn(program: String, arguments: List[String]) Result[Subprocess, Error]

type Capture:
    calls: Int

impl Runner for Capture:
    var fn run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Int?,
        timeout: Duration?
    ) Result[CommandOutput, Error]:
        self.calls += 1
        return ok(CommandOutput(0, input, "".to_bytes(), 0))

    fn spawn(program: String, arguments: List[String]) Result[Subprocess, Error]:
        return error(
            Error(
                "process: service unavailable", kind: ErrorCategory.Unavailable
            )
        )

export fn main() Int:
    var capture = Capture(0)
    let _bound = capture.run
    let _r = capture.run("x", [], "".to_bytes())
    let _o = CsvOptions()
    return 0
