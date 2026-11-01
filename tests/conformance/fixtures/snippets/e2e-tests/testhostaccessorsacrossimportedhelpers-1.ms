# conform: tags=diagnostics,modules,stdlib-io,stdlib-time,tier-io
# conform: phase=check
# conform: origin=tests/e2e/e2e_test.go:434 TestHostAccessorsAcrossImportedHelpers
import stdout from "@std/io/io.ms"
import monotonic from "@std/os/time.ms"
import Instant from "@std/os/time.ms"

export fn now() Instant:
    return monotonic()

export fn close_output() Unit:
    stdout().close()
