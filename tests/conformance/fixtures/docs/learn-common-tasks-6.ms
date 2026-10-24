# conform: tags=control-flow,diagnostics,faults,interpolation,modules,stdlib-io,stdlib-process,tier-io,try-result
# conform: phase=check
# conform: origin=documentation/learn/common-tasks.md:150
from "@std/process.ms" import arguments
from "@std/io.ms" import stdout

def show(number: Int) -> Result[Unit, Error]:
    try stdout().write(f"{number}\n")
    return stdout().flush()

export def main() -> Int:
    let number = arguments().get(0, default: "42").parse_int()
    if let value = number:
        if show(value).is_ok():
            return 0
    return 1
