// conform: tags=maps,faults,tier-core
// conform: phase=run
// conform: origin=Map and Bytes indexing
import stdout from "@std/io/io.ms"

fn main() Void {
	scores := {"ann": 1, "bob": 2}
	void stdout().write(f"{scores["ann"]}\n")
	void stdout().write(f"{scores["eve"]}\n")
}
