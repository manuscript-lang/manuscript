# conform: tags=control-flow,diagnostics,interpolation,modules,stdlib-io,stdlib-process,tier-io,try-result
# conform: phase=check
# conform: origin=documentation/learn/common-tasks.md:39
from "@std/process.ms" import arguments
from "@std/io.ms" import stdout

def run() -> Result[Unit, Error]:
    for name in arguments():
        try stdout().write(f"Hello, {name}!\n")
    return stdout().flush()

export def main() -> Int:
    if run().is_error():
        return 1

    return 0
