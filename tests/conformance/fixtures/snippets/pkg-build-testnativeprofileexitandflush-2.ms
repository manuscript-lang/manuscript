# conform: tags=faults,modules,stdlib-faults,tier-stdlib
# conform: phase=run
# conform: origin=pkg/build/profile_test.go:29 TestNativeProfileExitAndFlush
import panic from "@std/core.ms"
export fn main() Int:
    return panic(message: "profile failure")
