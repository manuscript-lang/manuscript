# conform: tags=diagnostics,modules,stdlib-io,stdlib-time,tier-io
# conform: phase=check
# conform: origin=pkg/build/profile_test.go:32 TestNativeProfileExitAndFlush
from "@std/time.ms" import duration, sleep
from "@std/io.ms" import stdout

export def main() -> Int:
    stdout().write(data: "ready\n")
    sleep(duration(nanoseconds: 60000000000))
    return 0
