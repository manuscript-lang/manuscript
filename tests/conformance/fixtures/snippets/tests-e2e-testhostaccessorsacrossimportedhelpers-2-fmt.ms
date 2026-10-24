# conform: tags=control-flow,formatter,match,modules,parser,stdlib-io,stdlib-time,tier-io
# conform: phase=parse
# conform: origin=tests/e2e/e2e_test.go:444 TestHostAccessorsAcrossImportedHelpers
from "./helper.ms" import now, close_output
from "@std/io.ms" import stdout
from "@std/time.ms" import clock

export def main() -> Int:
    let before = now()
    if clock().now() - before < 0.milliseconds:
        return 1

    close_output()

    let cause = match stdout().write(""):
        case ok(_):
            return 3
        case error(cause): cause

    match cause:
        case Closed:
            return 0
        case _:
            return 4
