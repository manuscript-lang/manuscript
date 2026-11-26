// conform: tags=faults,formatter,modules,stdlib-faults,tier-stdlib
// conform: phase=run,parse
// conform: origin=pkg/build/profile_test.go:29 TestNativeProfileExitAndFlush
import panic from "@std/core.ms"

export fn main() Int {
	return panic(message: "profile failure")
}
// expect-exit: 134
// expect-stderr: profile failure
// expect-stderr:   at testnativeprofileexitandflush-2.ms:7 in main
