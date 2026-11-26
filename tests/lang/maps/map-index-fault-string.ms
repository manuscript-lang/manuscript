// conform: tags=maps,faults,tier-core
// conform: phase=run
// conform: origin=Map and Bytes indexing
import stdout from "@std/io/io.ms"

fn main() Void {
	scores := {"ann": 1, "bob": 2}
	void stdout().write(f"{scores["ann"]}\n")
	void stdout().write(f"{scores["eve"]}\n")
}
// expect-exit: 134
// expect-stdout: 1
// expect-stderr: map key not found: "eve"
// expect-stderr:   at map-index-fault-string.ms:9 in main
