# conform: tags=formatter,modules,parser,stdlib-io,stdlib-time,tier-io
# conform: phase=parse
# conform: origin=pkg/build/profile_test.go:32 TestNativeProfileExitAndFlush
from "@std/time.ms" import nanoseconds, sleep
from "@std/io.ms" import stdout

export def main() -> Int:
    let _ = stdout().write(data: "ready\n")
    sleep(nanoseconds(60000000000))
    return 0
