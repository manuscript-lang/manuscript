// conform: tags=lists,faults,perf,tier-core
// conform: phase=run
// conform: origin=range pass: relational bounds proofs
import stdout from "@std/io/io.ms"

fn stride(a List[Int]) Int {
	var t = 0
	for i in 0..a.length() / 3 + 1 {
		t += a[i * 3 + 2]
	}
	return t
}

fn main() Void {
	void stdout().write(f"{stride([1, 2, 3, 4, 5, 6, 7])}\n")
}
// expect-exit: 134
// expect-stderr: index 8 out of range for length 7; use get_or(index, default) to avoid the fault
// expect-stderr:   at bounds-fault-stride.ms:9 in stride
// expect-stderr:   at bounds-fault-stride.ms:15 in main
