# conform: tags=control-flow,faults,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io
# conform: phase=parse
# conform: origin=documentation/_index.md:10
from "@std/process.ms" import arguments
from "@std/io.ms" import stdout

export def main() -> Int:
    let name = arguments().get(0, default: "world")
    let message = f"Hello, {name}!\n"
    if stdout().write(message).is_error():
        return 1

    return 0
