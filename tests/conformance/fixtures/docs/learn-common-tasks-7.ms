# conform: tags=control-flow,diagnostics,faults,interpolation,modules,stdlib-io,stdlib-json,stdlib-process,strings,tier-io,try-result
# conform: phase=check
# conform: origin=documentation/learn/common-tasks.md:177
from "@std/process.ms" import arguments
from "@std/json.ms" import parse
from "@std/io.ms" import stdout

def run() -> Result[Unit, Error]:
    let text = try parse[String](arguments().get(0, default: "\"hello\""))
    try stdout().write(f"{text}\n")
    return stdout().flush()

export def main() -> Int:
    if run().is_error():
        return 1

    return 0
