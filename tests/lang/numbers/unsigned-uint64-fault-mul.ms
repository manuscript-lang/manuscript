// conform: tags=numbers,faults,tier-core
// conform: phase=run
// conform: origin=unsigned integer types UInt64 inline checks

import stdout from "@std/io/io.ms"

fn main() Void {
	top UInt64 := 18446744073709551615
	one UInt64 := 1
	void stdout().write("before\n")

	c := top * top
	void stdout().write(f"{c}\n")
}
// expect-exit: 1
// expect-stderr: <DIR>/unsigned-uint64-fault-mul.ms:9:5: type: local binding one is never read; remove it, use it, or name it with a leading '_' to ignore it
// expect-stderr:    |
// expect-stderr:  9 |     one UInt64 := 1
// expect-stderr:    |     ^
// expect-stderr: 1 error; fix them and re-run (ms check <file> --json gives the same diagnostics as structured data)
