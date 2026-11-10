// conform: tags=control-flow,faults,formatter,interpolation,modules,parser,records,stdlib-io,stdlib-json,stdlib-process,strings,tier-io,try-result
// conform: phase=parse
// conform: origin=documentation/learn/common-tasks.md:204
import arguments from "@std/os/env.ms"
import parse, stringify from "@std/data/json.ms"
import stdout from "@std/io/io.ms"

type Config:
    name: String
    enabled: Bool = true

fn run() Result[Unit, Error]:
    let text = arguments().get(0, default: "\{\"name\":\"Sam\"\}")
    let encoded = try parse[Config](text)
        | try stringify
    try stdout().write("{encoded}\n")
    return stdout().flush()

fn main() Unit!:
    try run()
