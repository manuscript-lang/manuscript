# conform: tags=faults,formatter,modules,parser,stdlib-faults,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/build/profile_test.go:29 TestNativeProfileExitAndFlush
from "@std/core.ms" import panic

export def main() -> Int:
    return panic(message: "profile failure")
