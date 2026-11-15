// conform: tags=faults,scope-cleanup,tier-io
// conform: phase=run
import panic from "@std/core.ms"
import stdout from "@std/io/io.ms"

type Marker:
	name: String

fn var Marker.close() Void!:
	void stdout().write("closed {self.name}\n")

fn main() Void:
	void stdout().write("start\n")
	marker := Marker("outer")
	panic("boom {marker.name}")
