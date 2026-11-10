// Runs the packaged ms for this host (built by package.ms) on the hello example, from a path that
// contains spaces. Usage: ms run tools/dist-check.ms
import (
	dist_arch, dist_os, file_sha256, host, note, run_program, capture from "./lib.ms",
	create_directory, temporary from "@std/os/fs.ms",
)

fn main() Int:
	if host() == "windows":
		note("dist-check supports Linux and macOS hosts")
		return 1

	name := "manuscript-rust-{dist_os()}-{dist_arch()}"
	staging := temporary("ms-dist-check-").get()
	base := "{staging.path()}/extracted distribution"
	create_directory(base, recursive: true).get()

	var code = run_program("tar", ["-xzf", "dist/{name}.tar.gz", "-C", base.clone()])
	if code != 0: return code

	bundle := "{base}/{name}"

	if file_sha256("{bundle}/LICENSE") != file_sha256("LICENSE"):
		note("packaged LICENSE differs from the repository license")
		return 1

	ms := "{bundle}/ms"
	hello := "{bundle}/examples/hello"
	code = run_program(ms, ["--version"])
	if code != 0: return code

	var out = capture(ms, ["run", "{hello}/ms.toml", "--", "first", "second"]).trim()

	if out != "Arguments: 2":
		note("ms run printed {out}")
		return 1

	exe := "{staging.path()}/hello"
	code = run_program(ms, ["build", "{hello}/ms.toml", "-o", exe.clone()])
	if code != 0: return code

	out = capture(exe, ["first", "second"]).trim()

	if out != "Arguments: 2":
		note("built hello printed {out}")
		return 1

	code = run_program(ms, ["test", "{hello}/test.ms"])
	if code == 0: print("dist-check ok")
	return code
