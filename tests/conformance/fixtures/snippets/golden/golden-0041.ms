// conform: tags=diagnostics
// conform: phase=check
import (
	stdout from "@std/io/io.ms",
	arguments from "@std/os/process.ms",
)

fn main() Void! {
	message := f"Arguments: {arguments().length()}\n"
	stdout().write(message)?
}
// expect-error: MS2002 5:5-5:14 module does not export arguments; another standard module exports it, so replace this import with: import arguments from "@std/os/env.ms"
// expect-error: MS2001 9:30 unknown binding arguments; add: import arguments from "@std/os/env.ms"
// expect-fix: 1:1-1:1 "import arguments from \"@std/os/env.ms\"\n"
