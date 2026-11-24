// conform: tags=diagnostics
// conform: phase=check
import (
	stderr, stdout from "@std/io/io.ms",
	arguments from "@std/os/process.ms",
)

export fn main() Int {
	args := arguments()
	_out := stdout().write(data: f"out={args[0]}\n")
	_err := stderr().write(data: "stderr\n")
	return 7
}
