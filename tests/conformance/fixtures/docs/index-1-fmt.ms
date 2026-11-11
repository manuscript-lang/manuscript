// conform: tags=control-flow,faults,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io
// conform: phase=parse
// conform: origin=documentation/_index.md:10
import (
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
)

fn main() Unit!:
	name := arguments().get(0, default: "world")
	message := "Hello, {name}!\n"
	stdout().write(message)?
