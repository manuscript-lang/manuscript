# conform: tags=control-flow,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io
# conform: phase=parse
# conform: origin=documentation/learn/getting-started.md:33
from "@std/process.ms" import arguments
from "@std/io.ms" import stdout

export def main() -> Int:
    let message = f"Arguments: {arguments().length()}\n"
    if stdout().write(message).is_error():
        return 1

    return 0
