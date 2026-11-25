// conform: tags=lists,faults,perf,tier-core
// conform: phase=run
// conform: origin=range pass: relational bounds proofs
import stdout from "@std/io/io.ms"

fn search(a List[Int], want Int) Int {
	var lo = 0
	var hi = a.length()

	while lo <= hi {
		mid := lo + (hi - lo) / 2
		if a[mid] == want {
			return mid
		}

		if a[mid] < want {
			lo = mid + 1
		} else {
			hi = mid - 1
		}
	}

	return -1
}

fn main() Void {
	void stdout().write(f"{search([1, 3, 5], 9)}\n")
}
// expect-exit: 134
// expect-stderr: index 3 out of range for length 3; use get_or(index, default) to avoid the fault
// expect-stderr:   at bounds-fault-search.ms:12 in search
// expect-stderr:   at bounds-fault-search.ms:27 in main
