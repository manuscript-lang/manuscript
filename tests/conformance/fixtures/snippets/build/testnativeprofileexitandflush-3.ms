// conform: tags=diagnostics,modules,stdlib-io,stdlib-time,tier-io
// conform: phase=check
// conform: origin=pkg/build/profile_test.go:32 TestNativeProfileExitAndFlush
import (
	stdout from "@std/io/io.ms",
	nanoseconds, sleep from "@std/time.ms",
)

fn main() Void {
	void stdout().write("ready\n")
	void sleep(nanoseconds(60000000000)).wait()
}
