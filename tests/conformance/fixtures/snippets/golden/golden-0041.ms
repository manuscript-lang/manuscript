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
