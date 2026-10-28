# conform: tags=diagnostics,modules,stdlib-io,stdlib-time,tier-io
# conform: phase=check
# conform: origin=pkg/build/profile_test.go:32 TestNativeProfileExitAndFlush
import {nanoseconds, sleep} from "@std/time.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let _ = stdout().write(data: "ready\n")
    sleep(nanoseconds(60000000000))
    return 0
