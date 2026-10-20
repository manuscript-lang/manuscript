# conform: tags=control-flow,formatter,match,modules,parser,stdlib-io,stdlib-time,tier-io
# conform: phase=parse
# conform: origin=tests/e2e/e2e_test.go:444 TestHostAccessorsAcrossImportedHelpers
import { now, close_output } from "./helper.ms"
import stdout from "@std/io.ms"
import clock from "@std/time.ms"

export fn main() Int:
    let before = now()
    if clock().now() - before < 0.milliseconds:
        return 1
    close_output()

    let cause = match stdout().write(""):
        ok(_):
            return 3
        error(cause): cause

    match cause:
        Closed:
            return 0
        _:
            return 4

