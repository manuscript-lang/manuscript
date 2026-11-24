// conform: tags=numbers,types,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 4
import stdout from "@std/io/io.ms"

fn main() Void {
	m Int8 := -128
	void stdout().write(f"{m.abs()}\n")
}
