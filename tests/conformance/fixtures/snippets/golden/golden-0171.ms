// conform: tags=diagnostics
// conform: phase=check
import (
	stdout from "@std/io/io.ms",
	nanoseconds, sleep from "@std/time.ms",
)

fn main() Void {
	stdout().write(data: "ready\n")
	sleep(nanoseconds(60000000000))
}
