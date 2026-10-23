# conform: tags=control-flow,faults,formatter,interpolation,modules,parser,stdlib-io,stdlib-json,stdlib-process,strings,tier-io,try-result
# conform: phase=parse
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
