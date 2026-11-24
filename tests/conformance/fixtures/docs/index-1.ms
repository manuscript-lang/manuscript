// conform: tags=control-flow,diagnostics,faults,interpolation,modules,stdlib-io,stdlib-process,tier-io
// conform: phase=check
// conform: origin=documentation/_index.md:10
import (
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
)

fn main() Void! {
	name := arguments().get_or(0, "world")
	message := f"Hello, {name}!\n"
	stdout().write(message)?
}
