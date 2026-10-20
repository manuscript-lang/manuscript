# conform: tags=match,modules,parser,stdlib-io,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/watch_test.go:27 TestRunWatchRebuildsAfterEdits
import stdout from "@std/io.ms"

export fn main() Int:
    match stdout().write(data: %q):
        ok(_):
            return 0
        error(_):
            return 1
