// Fetches the pinned shared LLVM library for this host (`toolchain/llvm-lib.lock`:
// release tag, version and the SHA-256 of each platform's archive) from
// manuscript-lang/llvm-bundle into .artifacts/llvm-lib (LLVM_LIB_WORK overrides it) and
// prints the absolute path of the library, which is what `MS_LLVM` takes. When
// GITHUB_ENV is set it also appends `MS_LLVM=<path>` there, so the later steps of a CI
// job use the library. Does nothing but print when the library is already there. With
// `tools` it fetches the same release's opt and llc instead (`llvm-tools`), prints their
// paths and exports MS_OPT and MS_LLC, so the process route can be timed against the
// library. Usage: ms run tools/fetch-llvm-lib.ms [-- tools]
import (
	arguments, working_directory from "@std/os/env.ms",
	append_file,
	canonicalize,
	create_directory,
	exists,
	read_file,
	remove,
	rename from "@std/os/fs.ms",

	dist_arch,
	dist_os,
	env,
	exe,
	file_sha256,
	note,
	run_program,
	run_program_in from "./lib.ms",
)

// The value after `key ` on the first lock line that starts with it.
fn lock_value(lock: String, key: String) String:
	for line in lock.split("\n"):
		if line.starts_with(f"{key} "): return line.slice(
			key.length() + 1,
			line.length(),
		).trim()
	return ""

// The digest the lock records for `asset`, or empty.
fn lock_digest(lock: String, asset: String) String:
	for line in lock.split("\n"):
		if line.ends_with(f"  {asset}"): return line.slice(0, 64)
	return ""

// The library inside an unpacked archive: `lib/libLLVM.so`, `lib/libLLVM.dylib` or
// `bin/LLVM-C.dll`.
fn library_path(target_os: String) String:
	if target_os == "darwin": return "lib/libLLVM.dylib"
	if target_os == "windows": return "bin/LLVM-C.dll"

	return "lib/libLLVM.so"

fn main() Int:
	root := working_directory().get()
	lock := (
		read_file(f"{root}/toolchain/llvm-lib.lock").wait().get().decode_utf8()
		or ""
	)
	tag := lock_value(lock, "tag")
	version := lock_value(lock, "version")
	target_os := dist_os()
	target_arch := dist_arch()
	tools := arguments().contains("tools")
	kind := if tools: "llvm-tools" else: "llvm-lib"
	asset := f"{kind}-{version}-{target_os}-{target_arch}.tar.gz"
	want := lock_digest(lock, asset)

	if want == "":
		note(f"toolchain/llvm-lib.lock has no digest for {asset}")
		return 1

	work := env("LLVM_LIB_WORK", f"{root}/.artifacts/llvm-lib")
	here := f"{work}/{tag}-{if tools: "tools-" else: ""}{target_os}-{target_arch}"
	library := if tools: f"{here}/bin/opt{exe()}" else: f"{here}/{library_path(target_os)}"

	if not exists(library).get_or(false):
		partial := f"{here}.tmp"
		void remove(partial.clone(), recursive: true)
		create_directory(partial.clone(), recursive: true).get()

		archive := f"{partial}/{asset}"
		url := f"https://github.com/manuscript-lang/llvm-bundle/releases/download/{tag}/{asset}"
		var code = run_program(
			"curl",
			[
				"--fail",
				"--location",
				"--retry",
				"3",
				"-sS",
				"-o",
				archive.clone(),
				url,
			],
		)
		if code != 0: return code

		got := file_sha256(archive.clone())

		if got != want:
			note(f"{asset} checksum mismatch: expected {want}, got {got}")
			return 1

		code = run_program_in("tar", ["-xzf", asset.clone()], partial.clone())
		if code != 0: return code

		void remove(archive.clone(), recursive: false)
		void remove(here.clone(), recursive: true)
		rename(partial.clone(), here.clone()).get()

	path := canonicalize(library).get()
	print(path)

	var exports = f"MS_LLVM={path}\n"

	if tools:
		llc := f"{path.slice(0, path.length() - f"opt{exe()}".length())}llc{exe()}"
		print(llc)
		exports = f"MS_OPT={path}\nMS_LLC={llc}\n"

	github_env := env("GITHUB_ENV", "")
	if github_env != "": append_file(github_env, exports).wait().get()
	return 0
