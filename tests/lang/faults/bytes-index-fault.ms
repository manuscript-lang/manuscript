// conform: tags=faults,tier-core
// conform: phase=run
// conform: origin=Map and Bytes indexing
import stdout from "@std/io/io.ms"

fn main() Void {
	data := "abc".to_bytes()
	void stdout().write(f"{data[-1]}\n")
	void stdout().write(f"{data[3]}\n")
}
// expect-exit: 134
// expect-stdout: 99
// expect-stderr: index 3 out of range for length 3; use get_or(index, default) to avoid the fault
// expect-stderr:   at bytes-index-fault.ms:9 in main
