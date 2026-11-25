// conform: tags=lists,tier-core
// conform: phase=run
// conform: origin=List.chunks gives an empty list for a non-positive size
import stdout from "@std/io/io.ms"

fn main() Void {
	void stdout().write(f"{[1, 2, 3].chunks(0).length()}\n")
}
