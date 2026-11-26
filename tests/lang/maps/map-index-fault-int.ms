// conform: tags=maps,faults,tier-core
// conform: phase=run
// conform: origin=Map and Bytes indexing
import stdout from "@std/io/io.ms"

fn main() Void {
	counts := {1: 10}
	var bump = counts.clone()
	bump[1] += 5
	void stdout().write(f"{bump[1]}\n")
	void stdout().write(f"{counts[2]}\n")
}
// expect-exit: 134
// expect-stdout: 15
// expect-stderr: map key not found: 2
// expect-stderr:   at map-index-fault-int.ms:11 in main
