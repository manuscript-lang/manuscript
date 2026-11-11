// conform: tags=diagnostics
// conform: phase=check
import stdout from "@std/io/io.ms"
import clock from "@std/time.ms"
import Instant from "@std/time.ms"

export fn now() Instant:
    return clock().now()

export fn close_output() Unit:
    stdout().close()
