// The Rust `ms`, for the stages the Manuscript front has not taken over (compiling and
// linking). `$MS_RUST_CLI` names it, defaulting to `ms-rust` on the PATH.
import environment from "@std/os/env.ms"

// The program that runs the Rust command line.
export fn rust_cli() String:
	env := environment().get_or(Map[String, String]())
	return env.get_or("MS_RUST_CLI", "ms-rust")
