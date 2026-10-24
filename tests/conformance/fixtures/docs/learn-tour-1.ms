# conform: tags=control-flow,modules,stdlib-io,tier-core
# conform: phase=run
# conform: origin=documentation/learn/tour.md:15
from "@std/io.ms" import stdout

export def main() -> Int:
    if stdout().write("Hello, Manuscript!\n").is_error():
        return 1

    return 0
