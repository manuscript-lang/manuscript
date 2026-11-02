# conform: tags=control-flow,diagnostics,match,modules,stdlib-io,stdlib-time,tier-io
# conform: phase=check
# conform: origin=tests/e2e/e2e_test.go:444 TestHostAccessorsAcrossImportedHelpers
import now, close_output from "./helper.ms"
import stdout from "@std/io/io.ms"
import monotonic from "@std/os/time.ms"

export fn main() Int:
    let before = now()
    if monotonic() - before < 0.milliseconds:
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
