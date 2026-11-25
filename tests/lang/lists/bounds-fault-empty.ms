// conform: tags=lists,faults,perf,tier-core
// conform: phase=run
// conform: origin=range pass: relational bounds proofs
import stdout from "@std/io/io.ms"

fn last_after_loop(a List[Int]) Int {
	var t = 0
	for i in 0..a.length() {
		t += a[i]
	}
	return t + a[a.length() - 1]
}

fn main() Void {
	void stdout().write(f"{last_after_loop([])}\n")
}
// expect-exit: 134
// expect-stderr: index -1 out of range for length 0; use get_or(index, default) to avoid the fault
// expect-stderr:   at bounds-fault-empty.ms:11 in last_after_loop
// expect-stderr:   at bounds-fault-empty.ms:15 in main
