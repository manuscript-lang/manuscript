# conform: tags=formatter,modules,parser,stdlib-io,stdlib-time,tier-io
# conform: phase=parse
# conform: origin=tests/e2e/e2e_test.go:434 TestHostAccessorsAcrossImportedHelpers
import stdout from "@std/io.ms"
import clock from "@std/time.ms"
import Instant from "@std/time.ms"

export fn now() Instant:
    return clock().now()

export fn close_output() Unit:
    stdout().close()
