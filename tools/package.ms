# Builds the Rust ms for a target: one binary with the native runtime embedded, archived as
# dist/manuscript-rust-<os>-<arch>.{tar.gz,zip} with a .sha256 beside it. The release runner for
# each target builds it natively.
# Usage: ms run tools/package.ms [-- OS ARCH]
import capture, dist_arch, dist_os, file_sha256, note, run from "./lib.ms"
import filesystem from "@std/fs.ms"
import arguments, control from "@std/process.ms"
import stdout from "@std/io.ms"

fn supported(target_os: String, target_arch: String) Bool:
    let key = "{target_os}/{target_arch}"
    return [
        "linux/amd64", "linux/arm64", "darwin/amd64", "darwin/arm64", "windows/amd64",
        "windows/arm64"
    ].contains(key)

export fn main() Int:
    let args = arguments()
    var target_os = dist_os()
    var target_arch = dist_arch()

    if args.length() == 2:
        target_os = args[0].clone()
        target_arch = args[1].clone()
    else if args.length() != 0:
        note("Usage: ms run tools/package.ms [-- OS ARCH]")
        return 2

    if not supported(target_os, target_arch):
        note("Unsupported distribution target: {target_os}/{target_arch}")
        return 1

    var executable = "ms"
    if target_os == "windows": executable = "ms.exe"

    # ms-native is built in release mode first; `ms-cli`'s build script embeds the archive.
    var code = run("cargo", ["xtask", "runtime"])
    if code != 0: return code

    # Debug sections are dropped from the shipped binary (symbol names stay for fault traces and
    # the profiler). The host triple is explicit so CARGO_BUILD_TARGET or `build.target` cannot move
    # the output away from where the copy below reads it.
    var triple = ""
    for line in capture("rustc", ["-vV"]).split("\n"):
        if line.starts_with("host: "): triple = line.slice(
            6, line.length()
        ).get("").trim()
    control().set_environment("CARGO_PROFILE_RELEASE_STRIP", "debuginfo").get()
    code = run(
        "cargo",
        [
            "build", "--release", "--locked", "-p", "ms-cli", "--target",
            triple.clone(), "--target-dir", "target"
        ]
    )
    if code != 0: return code

    let fs = filesystem()
    let name = "manuscript-rust-{target_os}-{target_arch}"
    fs.create_directory("dist", recursive: true).get()

    let staging = fs.temporary("ms-package-").get()
    let bundle = "{staging.path()}/{name}"
    fs.create_directory("{bundle}/examples/hello/src", recursive: true).get()
    fs.copy_file("target/{triple}/release/{executable}", "{bundle}/{executable}").get()
    fs.copy_file("examples/hello/ms.toml", "{bundle}/examples/hello/ms.toml").get()
    fs.copy_file("examples/hello/test.ms", "{bundle}/examples/hello/test.ms").get()
    fs.copy_file(
        "examples/hello/src/main.ms", "{bundle}/examples/hello/src/main.ms"
    ).get()

    # `copy_file` writes private modes; the archive carries the usual ones.
    for dir in ["", "/examples", "/examples/hello", "/examples/hello/src"]:
        fs.chmod("{bundle}{dir}", 493).get()
    fs.chmod("{bundle}/{executable}", 493).get()
    for file in ["ms.toml", "test.ms", "src/main.ms"]:
        fs.chmod("{bundle}/examples/hello/{file}", 420).get()

    var archive = "dist/{name}.tar.gz"
    var archive_name = "{name}.tar.gz"

    if target_os == "windows":
        archive = "dist/{name}.zip"
        archive_name = "{name}.zip"

        let _ = fs.remove(archive.clone(), recursive: false)
        let zip_path = fs.canonicalize("dist").get()
        control().change_directory(staging.path()).get()
        code = run(
            "7z",
            [
                "a", "-tzip", "-bso0", "{zip_path}/{archive_name}", name.clone()
            ]
        )
    else:
        code = run("tar", ["-C", staging.path(), "-czf", archive.clone(), name.clone()])

    if code != 0: return code

    let digest = file_sha256(archive)
    fs.write_file("{archive}.sha256", "{digest}  {archive_name}\n", replace: true).get()
    stdout().write("{archive}\n").get()
    return 0
