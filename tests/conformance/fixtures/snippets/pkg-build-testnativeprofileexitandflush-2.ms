# conform: tags=faults,modules,stdlib-faults,tier-stdlib
# conform: phase=run
# conform: origin=pkg/build/profile_test.go:29 TestNativeProfileExitAndFlush
from "@std/core.ms" import panic

export def main() -> Int:
    return panic(message: "profile failure")
