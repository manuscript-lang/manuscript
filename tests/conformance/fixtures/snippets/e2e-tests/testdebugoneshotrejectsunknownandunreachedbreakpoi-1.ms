# conform: tags=modules,stdlib-io,tier-core
# conform: phase=run
# conform: origin=tests/e2e/debug_script_test.go:125 TestDebugOneShotRejectsUnknownAndUnreachedBreakpoints
import stdout from "@std/io/io.ms"

fn never() Int:
    return 1

export fn main() Int:
    let _written = stdout().write(data: "TARGET_RAN\n")
    return 0
