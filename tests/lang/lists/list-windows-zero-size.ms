// conform: tags=lists,tier-core
// conform: phase=run
// conform: origin=List.windows gives an empty list for a non-positive size
import stdout from "@std/io/io.ms"

fn main() Void {
	void stdout().write(f"{[1, 2, 3].windows(0).length()}\n")
}
// expect-exit: 0
// expect-stdout: 0
