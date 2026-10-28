# conform: tags=control-flow,faults,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io,try-result
# conform: phase=parse
# conform: origin=documentation/learn/common-tasks.md:150
import arguments from "@std/process.ms"
import stdout from "@std/io.ms"

fn show(number: Int) Result[Unit, Error]:
    try stdout().write("{number}\n")
    return stdout().flush()

export fn main() Int:
    let number = arguments().get(0, default: "42").parse_int()
    if let value = number:
        if show(value).is_ok():
            return 0
    return 1
