// conform: tags=control-flow,formatter,modules,stdlib-io,tier-core,try-result
// conform: phase=run,parse
// conform: origin=documentation/learn/common-tasks.md:15
import stdout from "@std/io/io.ms"

fn run() Result[Void, Error] {
	stdout().write("Hello, Manuscript!\n")?
	return stdout().flush()
}

fn main() Void! {
	run()?
}
