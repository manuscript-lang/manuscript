# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "msrt_string_to_bytes"

from "@std/process.ms" import Subprocess, CommandOutput, CommandError
from "@std/bytes.ms" import Bytes
from "@std/time.ms" import Duration
from "@std/csv.ms" import CsvOptions

interface Runner:
    var def run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[CommandOutput, CommandError]
    def spawn(program: String, arguments: List[String]) -> Result[Subprocess, CommandError]

type Capture:
    calls: Int

impl Runner for Capture:
    var def run(
        program: String,
        arguments: List[String],
        input: Bytes,
        max_output_bytes: Optional[Int],
        timeout: Optional[Duration]
    ) -> Result[CommandOutput, CommandError]:
        self.calls += 1
        return ok(CommandOutput(0, input, "".to_bytes()))

    def spawn(program: String, arguments: List[String]) -> Result[Subprocess, CommandError]:
        return error(CommandError.Unavailable)

export def main() -> Int:
    var capture = Capture(0)
    let bound = capture.run
    let r = capture.run("x", [], "".to_bytes())
    let o = CsvOptions()
    return 0
