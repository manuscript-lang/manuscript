// conform: tags=faults,scope-cleanup,tier-io
// conform: phase=run
import (
	panic from "@std/core.ms",
	stdout from "@std/io/io.ms",
)

type Marker {
	name String
}

fn move Marker.close() Void! {
	void stdout().write(f"closed {self.name}\n")
}

fn main() Void {
	void stdout().write("start\n")

	marker := Marker("outer")
	panic(f"boom {marker.name}")
}
// expect-exit: 134
// expect-stdout: start
// expect-stdout: closed outer
// expect-stderr: boom outer
// expect-stderr:   at fault-exit-runs-open-scope-closes.ms:20 in main
