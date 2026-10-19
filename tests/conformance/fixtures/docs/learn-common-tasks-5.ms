# conform: tags=control-flow,interpolation,modules,stdlib-io,tier-core,try-result
# conform: phase=run
# conform: origin=documentation/learn/common-tasks.md:120
import {stdin, stdout, read_line} from "@std/io.ms"

fn run() Result[Unit, Error]:
    let input = stdin()
    while true:
        let line = try read_line(input, max_bytes: 4096)
        if let text = line:
            try stdout().write("{text}\n")
        else:
            break
    return stdout().flush()

export fn main() Int:
    if run().is_error():
        return 1
    return 0
