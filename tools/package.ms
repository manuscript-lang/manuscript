// Builds `ms` for a target and archives it as
// dist/manuscript-rust-<os>-<arch>.{tar.gz,zip} with a .sha256 beside it. `ms` is the
// Manuscript front (tools/ms/main.ms over libms) and
// `ms-rust`, beside it, is the Rust command line it hands the stages C does not cover to; the
// front finds it in its own directory. The release runner for each target builds both
// natively. Usage: ms run tools/package.ms [-- OS ARCH]
import (
	arguments,
	change_directory,
	set_environment,
	working_directory from "@std/os/env.ms",
	chmod, copy, create_directory, remove, temporary, write_file from "@std/os/fs.ms",

	capture, dist_arch, dist_os, env, file_sha256, note, run_program from "./lib.ms",
)

fn supported(target_os: String, target_arch: String) Bool:
	key := f"{target_os}/{target_arch}"
	return [
		"linux/amd64", "linux/arm64", "darwin/amd64", "darwin/arm64", "windows/amd64",
		"windows/arm64"
	].contains(key)

fn main() Int:
	args := arguments()
	var target_os = dist_os()
	var target_arch = dist_arch()

	if args.length() == 2:
		target_os = args[0].clone()
		target_arch = args[1].clone()
	else if not args.is_empty():
		note("Usage: ms run tools/package.ms [-- OS ARCH]")
		return 2

	if not supported(target_os, target_arch):
		note(f"Unsupported distribution target: {target_os}/{target_arch}")
		return 1

	executable := if target_os == "windows": "ms.exe" else: "ms"

	// ms-native is built in release mode first; `ms-cli`'s build script embeds the
	// archive.
	var code = run_program("cmake", ["-P", "cmake/BuildRuntime.cmake"])
	if code != 0: return code

	// Debug sections are dropped from the shipped binary (symbol names stay for fault
	// traces and the profiler). The host triple is explicit so CARGO_BUILD_TARGET or
	// `build.target` cannot move the output away from where the copy below reads it.
	var triple = ""
	for line in capture("rustc", ["-vV"]).split("\n"):
		if line.starts_with("host: "): triple = line.slice(6, line.length()).trim()
	set_environment("CARGO_PROFILE_RELEASE_STRIP", "debuginfo").get()
	code = run_program(
		"cargo",
		[
			"build",
			"--release",
			"--locked",
			"-p",
			"ms-cli",
			"--target",
			triple.clone(),
			"--target-dir",
			"target",
		],
	)
	if code != 0: return code

	name := f"manuscript-rust-{target_os}-{target_arch}"
	create_directory("dist", recursive: true).get()

	staging := temporary("ms-package-").get()
	bundle := f"{staging.path()}/{name}"
	create_directory(f"{bundle}/examples/hello/src", recursive: true).get()

	rust := f"target/{triple}/release/{executable}"
	rust_name := if target_os == "windows": "ms-rust.exe" else: "ms-rust"
	copy(rust, f"{bundle}/{rust_name}").get()

	// The front links libms with the tool entry points, built here for this host.
	// Windows programs use the llvm-mingw ABI, so libms is built with the same clang as
	// the runtime.
	var configure = [
		"-S", ".", "-B", "target/cmake/tools", "-G", "Ninja", "-DMS_BUILD_RUNTIME=OFF"
	]
	mingw := env("MS_MINGW", "")

	if target_os == "windows" and mingw != "":
		mingw_triple := if target_arch == "arm64": "aarch64-w64-mingw32" else: "x86_64-w64-mingw32"
		configure.append(f"-DCMAKE_C_COMPILER={mingw}/bin/{mingw_triple}-clang.exe")

	code = run_program("cmake", configure)
	if code != 0: return code

	code = run_program(
		"cmake",
		["--build", "target/cmake/tools", "--target", "ms_tool"],
	)
	if code != 0: return code

	code = run_program(
		rust,
		[
			"build", "tools/ms/main.ms", "--build-type", "Release", "--link",
			"target/cmake/tools/compiler/libmstool.a", "-o", f"{bundle}/{executable}"
		],
	)
	if code != 0: return code

	copy("LICENSE", f"{bundle}/LICENSE").get()
	copy("examples/hello/ms.toml", f"{bundle}/examples/hello/ms.toml").get()
	copy("examples/hello/test.ms", f"{bundle}/examples/hello/test.ms").get()
	copy("examples/hello/src/main.ms", f"{bundle}/examples/hello/src/main.ms").get()

	// `copy` writes private modes; the archive carries the usual ones.
	for dir in ["", "/examples", "/examples/hello", "/examples/hello/src"]:
		chmod(f"{bundle}{dir}", 493).get()
	chmod(f"{bundle}/{executable}", 493).get()
	chmod(f"{bundle}/{rust_name}", 493).get()
	chmod(f"{bundle}/LICENSE", 420).get()
	for file in ["ms.toml", "test.ms", "src/main.ms"]:
		chmod(f"{bundle}/examples/hello/{file}", 420).get()

	var archive = f"dist/{name}.tar.gz"
	var archive_name = f"{name}.tar.gz"

	if target_os == "windows":
		archive = f"dist/{name}.zip"
		archive_name = f"{name}.zip"
		void remove(archive.clone(), recursive: false)

		root := working_directory().get()
		change_directory(staging.path()).get()
		code = run_program(
			"7z",
			[
				"a",
				"-tzip",
				"-bso0",
				f"{root}/dist/{archive_name}",
				name.clone(),
			],
		)

		// The checksum below reads the archive by its repository-relative path.
		change_directory(root).get()
	else:
		code = run_program(
			"tar",
			["-C", staging.path(), "-czf", archive.clone(), name.clone()],
		)

	if code != 0: return code

	digest := file_sha256(archive)
	write_file(f"{archive}.sha256", f"{digest}  {archive_name}\n", replace: true).wait().get()
	print(f"{archive}")
	return 0
