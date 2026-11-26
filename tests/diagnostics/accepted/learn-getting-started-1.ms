// conform: tags=control-flow,diagnostics,formatter,interpolation,modules,stdlib-io,stdlib-process,tier-io
// conform: phase=check,parse
// conform: origin=documentation/learn/getting-started.md:33
import arguments from "@std/os/env.ms"

fn main() Void {
	print(f"Arguments: {arguments().length()}")
}
// expect-exit: 0
