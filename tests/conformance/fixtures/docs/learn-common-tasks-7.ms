# conform: tags=control-flow,diagnostics,faults,interpolation,modules,stdlib-io,stdlib-json,stdlib-process,strings,tier-io,try-result
# conform: phase=check
# conform: origin=documentation/learn/common-tasks.md:177
import arguments from "@std/process.ms"
import parse from "@std/json.ms"
import stdout from "@std/io.ms"

fn run() Result[Unit, Error]:
    let text = try parse[String](arguments().get(0, default: "\"hello\""))
    try stdout().write("{text}\n")
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1

    return 0
