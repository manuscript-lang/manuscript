# conform: tags=formatter,modules,parser,stdlib-io,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/debug_script_test.go:125 TestDebugOneShotRejectsUnknownAndUnreachedBreakpoints
from "@std/io.ms" import stdout

def never() -> Int:
    return 1

export def main() -> Int:
    let _written = stdout().write(data: "TARGET_RAN\n")
    return 0
