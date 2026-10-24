# conform: tags=control-flow,modules,stdlib-io,tier-core,try-result
# conform: phase=run
# conform: origin=documentation/learn/common-tasks.md:15
from "@std/io.ms" import stdout

def run() -> Result[Unit, Error]:
    try stdout().write("Hello, Manuscript!\n")
    return stdout().flush()

export def main() -> Int:
    if run().is_error():
        return 1

    return 0
