// conform: tags=lists,faults,perf,tier-core
// conform: phase=run
// conform: origin=range pass: relational bounds proofs
import stdout from "@std/io/io.ms"

fn rows(g List[List[Int]]) Int {
	var t = 0
	for j in 0..g[0].length() {
		t += g[1][j]
	}
	return t
}

fn main() Void {
	void stdout().write(f"{rows([[1, 2, 3], [4]])}\n")
}
// expect-exit: 134
// expect-stderr: index 1 out of range for length 1; use get_or(index, default) to avoid the fault
// expect-stderr:   at bounds-fault-rows.ms:9 in rows
// expect-stderr:   at bounds-fault-rows.ms:15 in main
