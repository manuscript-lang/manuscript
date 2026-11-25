// conform: tags=formatter,modules,parser,stdlib-io,stdlib-time,tier-io
// conform: phase=parse
// conform: origin=pkg/build/profile_test.go:32 TestNativeProfileExitAndFlush
import (
	stdout from "@std/io/io.ms",
	nanoseconds, sleep from "@std/time.ms",
)

fn main() Void {
	void stdout().write("ready\n")
	sleep(nanoseconds(60000000000)).wait()
}
// expect-format: unchanged
