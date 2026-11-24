// Shared helpers for the repository tools in this directory. Run a tool from the
// repository root with `ms run tools/<name>.ms [-- arguments]`.
import (
	sha256 from "@std/crypto/crypto.ms",
	hex_encode from "@std/data/encoding.ms",
	stderr from "@std/io/io.ms",
	environment, set_environment, working_directory from "@std/os/env.ms",
	canonicalize, read_file from "@std/os/fs.ms",
	SpawnOptions, Stdio, run, spawn from "@std/os/process.ms",
	Os, os, system_info from "@std/os/system.ms",
)

// `linux`, `macos` or `windows`.
export fn host() String:
	family := os()
	if family == Os.Macos: return "macos"
	if family == Os.Windows: return "windows"

	return "linux"

// `.exe` on Windows, else empty.
export fn exe() String:
	if host() == "windows": return ".exe"
	return ""

// The distribution OS name used by archives: `linux`, `darwin` or `windows`.
export fn dist_os() String:
	if host() == "macos": return "darwin"
	return host()

// The distribution architecture name: `amd64` or `arm64`. The runtime reports the
// architecture ms was built for; `uname -m` in an MSYS2 shell on Windows arm64 runs as
// an emulated x86-64 process and says `x86_64`.
export fn dist_arch() String:
	if system_info().architecture == "arm64": return "arm64"
	return "amd64"

// Prints `message` and a newline to standard error.
export fn note(message String) Void:
	stderr().write(f"{message}\n").get()

// The value of environment variable `name`, or `fallback`.
export fn env(name String, fallback String) String:
	all := environment().get_or(Map[String, String]())
	value := all.get(name)
	if value != null: return value.clone()

	return fallback.clone()

// A process exit status limited to what `main` may return.
export fn status(code Int) Int:
	if code < 0 or code > 125: return 125
	return code

// Runs `program` with the parent's streams and returns its exit status; the PATH is
// searched. A program that cannot start, or one that ends with a status above 125,
// reports 125.
export fn run_program(program String, arguments List[String]) Int:
	return run_program_in(program, arguments, null)

// `run_program` in the directory `cwd` (the caller's when none). A path with a drive
// letter in an argument reads as `host:file` to GNU tar, so a caller on Windows names
// files relative to `cwd` instead.
export fn run_program_in(program String, arguments List[String], cwd String?) Int:
	if child := spawn(
		program,
		arguments,
		SpawnOptions(
			stdin: Stdio.Null,
			stdout: Stdio.Inherit,
			stderr: Stdio.Inherit,
			cwd: cwd.clone(),
		),
	):
		return status(child.wait().clone().get_or(125))

	note(f"cannot start {program}")
	return 125

// Runs `program` and returns its standard output; empty when it cannot run or fails.
export fn capture(program String, arguments List[String]) String:
	if out := run(program, arguments).wait():
		if out.exit_code == 0: return (out.stdout.decode_utf8() or "").clone()
	return ""

// Whether `program` runs and exits zero with `arguments`.
export fn works(program String, arguments List[String]) Bool:
	if out := run(program, arguments).wait(): return out.exit_code == 0
	return false

// The SHA-256 of the file at `path` as lowercase hex.
export fn file_sha256(path String) String:
	data := read_file(path).wait().get()
	return hex_encode(sha256(data))

// Builds the counting runtime (`cmake --preset stats`: live blocks, parks and copies
// printed on standard error at exit, see design/proposals/c-runtime-stats-variant.md)
// and points MS_RUNTIME at it, so the tools run the programs with the ci build's ms
// linked against the counting archives. Only the project's own runtime archives are
// rebuilt: the vendored libraries come from the ci tree. Returns a nonzero status when
// a build fails.
export fn use_stats_runtime() Int:
	for step in [
		["--preset", "stats"],
		["--build", "--preset", "stats", "--target", "stats-runtime"],
	]:
		out := run("cmake", step.clone()).wait()

		if out.is_error() or out.get().exit_code != 0:
			note("cmake " + step.join(" ") + " failed")
			if out.is_ok(): note(
				(out.get().stderr.decode_utf8() or "") + (
					out.get().stdout.decode_utf8()
					or ""
				)
			)
			return 1

	root := working_directory().get()
	stats := f"{root}/.artifacts/build/stats"
	paths := (
		read_file(
			f"{stats}/generated/ms_runtime_paths.h"
		).wait().get().decode_utf8()
		or ""
	)
	var separator = ":"
	if host() == "windows": separator = ";"

	var archives = List[String]()

	for line in paths.split("\n"):
		prefix := "#define MS_BUILD_RUNTIME \""
		if not line.starts_with(prefix): continue

		// Up to the closing quote: a Windows header may end the line with CR LF.
		list := line.slice(prefix.length(), line.last_index_of("\"") or line.length())

		for archive in list.split(separator):
			name := archive.slice(
				(archive.last_index_of("/") or - 1) + 1,
				archive.length(),
			)

			if name.starts_with("libms_"):
				archives.append(archive.clone())
			else:
				archives.append(archive.replace(stats, f"{root}/.artifacts/build/ci"))

	set_environment("MS_RUNTIME", archives.join(separator)).get()
	return 0

// The ms that runs the programs under test: `MS` (resolved against `root` when
// relative), else the CMake build's ms (`cmake --preset ci`), which the Makefile also
// names.
export fn tool_ms(root String) String:
	named := env("MS", "")
	if named == "": return f"{root}/.artifacts/build/ci/src/cli/ms{exe()}"
	if named.starts_with("/") or named.contains(":"): return named

	return f"{root}/{named}{exe()}"
