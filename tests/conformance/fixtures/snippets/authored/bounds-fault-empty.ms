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
