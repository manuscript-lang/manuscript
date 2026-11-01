# conform: tags=formatter,modules,parser,stdlib-io,stdlib-time,tier-io
# conform: phase=parse
# conform: origin=pkg/build/profile_test.go:32 TestNativeProfileExitAndFlush
import nanoseconds, sleep from "@std/os/time.ms"
import stdout from "@std/io/io.ms"

export fn main() Int:
    let _ = stdout().write(data: "ready\n")
    sleep(nanoseconds(60000000000))
    return 0
