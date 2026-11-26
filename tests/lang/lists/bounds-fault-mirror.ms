// conform: tags=lists,faults,perf,tier-core
// conform: phase=run
// conform: origin=range pass: relational bounds proofs
import stdout from "@std/io/io.ms"

fn mirror(a List[Int]) Int {
	var t = 0
	for i in 0..a.length() / 2 {
		t += a[a.length() - i]
	}
	return t
}

fn main() Void {
	void stdout().write(f"{mirror([1, 2, 3, 4])}\n")
}
// expect-exit: 134
// expect-stderr: index 4 out of range for length 4; use get_or(index, default) to avoid the fault
// expect-stderr:   at bounds-fault-mirror.ms:9 in mirror
// expect-stderr:   at bounds-fault-mirror.ms:15 in main
