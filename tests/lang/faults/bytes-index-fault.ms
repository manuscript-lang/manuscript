// conform: tags=faults,tier-core
// conform: phase=run
// conform: origin=Map and Bytes indexing
import stdout from "@std/io/io.ms"

fn main() Void {
	data := "abc".to_bytes()
	void stdout().write(f"{data[-1]}\n")
	void stdout().write(f"{data[3]}\n")
}
