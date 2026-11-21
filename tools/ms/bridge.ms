// The Rust `ms`, for the stages the Manuscript front has not taken over (compiling and
// linking). `$MS_RUST_CLI` names it; else `ms-rust` beside this program, which is where a
// distribution puts it; else `ms-rust` on the PATH.
import environment from "@std/os/env.ms"
import exists from "@std/os/fs.ms"
import dirname, join from "@std/os/path.ms"
import process_info from "@std/os/process.ms"

// The file name of the Rust command on this system.
fn rust_name(os: String) String:
	if os == "windows": return "ms-rust.exe"
	return "ms-rust"

// The program that runs the Rust command line.
// ms: allow_effect std.process.read
// ms: allow_effect std.fs.read
export fn rust_cli() String:
	env := environment().get_or(Map[String, String]())
	if named := env.get("MS_RUST_CLI"): return named.clone()

	info := process_info()
	if info.is_error(): return "ms-rust"

	beside := join([dirname(info.get().executable), rust_name(info.get().os)])
	if exists(beside).get_or(false): return beside

	return "ms-rust"
