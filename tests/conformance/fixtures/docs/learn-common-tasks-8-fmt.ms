# conform: tags=control-flow,faults,formatter,interpolation,modules,parser,records,stdlib-io,stdlib-json,stdlib-process,strings,tier-io,try-result
# conform: phase=parse
# conform: origin=documentation/learn/common-tasks.md:204
from "@std/process.ms" import arguments
from "@std/json.ms" import parse, stringify
from "@std/io.ms" import stdout

type Config:
    name: String
    enabled: Bool = True

def run() -> Result[Unit, Error]:
    let text = arguments().get(0, default: "{\"name\":\"Sam\"}")
    let encoded = try parse[Config](text)
        | try stringify
    try stdout().write(f"{encoded}\n")
    return stdout().flush()

export def main() -> Int:
    if run().is_error():
        return 1

    return 0
