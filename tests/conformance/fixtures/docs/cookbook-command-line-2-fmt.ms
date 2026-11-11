// conform: tags=control-flow,formatter,interpolation,modules,parser,stdlib-io,stdlib-process,tier-io,try-result
// conform: phase=parse
// conform: origin=documentation/learn/common-tasks.md:39
import (
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
)

fn run() Result[Unit, Error]:
	for name in arguments():
		stdout().write("Hello, {name}!\n")?
	return stdout().flush()

fn main() Unit!:
	run()?
