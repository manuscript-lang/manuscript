// conform: tags=control-flow,diagnostics,faults,interpolation,modules,stdlib-io,stdlib-json,stdlib-process,strings,tier-io,try-result
// conform: phase=check
// conform: origin=documentation/learn/common-tasks.md:177
import (
	parse from "@std/data/json.ms",
	stdout from "@std/io/io.ms",
	arguments from "@std/os/env.ms",
)

fn run() Result[Unit, Error]:
	text := parse[String](arguments().get(0, default: "\"hello\""))?
	stdout().write("{text}\n")?
	return stdout().flush()

fn main() Unit!:
	run()?
