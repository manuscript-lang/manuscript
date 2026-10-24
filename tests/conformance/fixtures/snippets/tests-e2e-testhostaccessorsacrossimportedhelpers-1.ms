# conform: tags=diagnostics,modules,stdlib-io,stdlib-time,tier-io
# conform: phase=check
# conform: origin=tests/e2e/e2e_test.go:434 TestHostAccessorsAcrossImportedHelpers
from "@std/io.ms" import stdout
from "@std/time.ms" import clock
from "@std/time.ms" import Instant

export def now() -> Instant:
    return clock().now()

export def close_output() -> Unit:
    stdout().close()
