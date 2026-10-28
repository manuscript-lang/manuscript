# conform: tags=control-flow,faults,formatter,interpolation,modules,parser,records,stdlib-io,stdlib-json,stdlib-process,strings,tier-io,try-result
# conform: phase=parse
# conform: origin=documentation/learn/common-tasks.md:204
import arguments from "@std/process.ms"
import {parse, stringify} from "@std/json.ms"
import stdout from "@std/io.ms"

type Config:
    name: String
    enabled: Bool = true

fn run() Result[Unit, Error]:
    let text = arguments().get(0, default: "\{\"name\":\"Sam\"\}")
    let encoded = try parse[Config](text)
        | try stringify
    try stdout().write("{encoded}\n")
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1

    return 0
