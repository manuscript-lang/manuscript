// Runs the packaged ms for this host (built by package.ms) on the hello example, from a
// path that contains spaces. Usage: ms run tools/dist-check.ms
import (
	create_directory, temporary from "@std/os/fs.ms",

	capture, dist_arch, dist_os, file_sha256, host, note, run_program from "./lib.ms",
)

fn main() Int:
	if host() == "windows":
		note("dist-check supports Linux and macOS hosts")
		return 1

	name := f"manuscript-rust-{dist_os()}-{dist_arch()}"
	staging := temporary("ms-dist-check-").get()
	base := f"{staging.path()}/extracted distribution"
	create_directory(base, recursive: true).get()

	var code = run_program("tar", ["-xzf", f"dist/{name}.tar.gz", "-C", base.clone()])
	if code != 0: return code

	bundle := f"{base}/{name}"

	if file_sha256(f"{bundle}/LICENSE") != file_sha256("LICENSE"):
		note("packaged LICENSE differs from the repository license")
		return 1

	ms := f"{bundle}/ms"
	hello := f"{bundle}/examples/hello"
	code = run_program(ms, ["--version"])
	if code != 0: return code

	var out = capture(ms, ["run", f"{hello}/ms.toml", "--", "first", "second"]).trim()

	if out != "Arguments: 2":
		note(f"ms run printed {out}")
		return 1

	exe := f"{staging.path()}/hello"
	code = run_program(ms, ["build", f"{hello}/ms.toml", "-o", exe.clone()])
	if code != 0: return code

	out = capture(exe, ["first", "second"]).trim()

	if out != "Arguments: 2":
		note(f"built hello printed {out}")
		return 1

	code = run_program(ms, ["test", f"{hello}/test.ms"])
	if code == 0: print("dist-check ok")
	return code
