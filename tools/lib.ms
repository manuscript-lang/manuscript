# Shared helpers for the repository tools in this directory. Run a tool from the repository root
# with `ms run tools/<name>.ms [-- arguments]`.
import (
    Stdio,
    os_type,
    environment,
    set_environment,
    run,
    spawn
) from "@std/os/process.ms"
import canonicalize, read_file from "@std/os/fs.ms"
import stderr from "@std/io/io.ms"
import hex_encode from "@std/data/encoding.ms"
import sha256 from "@std/crypto.ms"

# `linux`, `macos` or `windows`.
export fn host() String:
    let os = os_type()
    if os == "Darwin": return "macos"
    if os == "Windows_NT": return "windows"

    return "linux"

# `.exe` on Windows, else empty.
export fn exe() String:
    if host() == "windows": return ".exe"

    return ""

# The distribution OS name used by archives: `linux`, `darwin` or `windows`.
export fn dist_os() String:
    if host() == "macos": return "darwin"

    return host()

# The distribution architecture name: `amd64` or `arm64`.
export fn dist_arch() String:
    let machine = capture("uname", ["-m"]).trim()
    if machine == "aarch64" or machine == "arm64" or machine == "ARM64": return "arm64"

    return "amd64"

# Prints `message` and a newline to standard error.
export fn note(message: String) Unit:
    stderr().write("{message}\n").get()

# The value of environment variable `name`, or `fallback`.
export fn env(name: String, fallback: String) String:
    let all = environment().get(Map[String, String]())
    if let value = all.get(name): return value.clone()

    return fallback

# A process exit status limited to what `main` may return.
export fn status(code: Int) Int:
    if code < 0 or code > 125: return 125

    return code

# Runs `program` with the parent's streams and returns its exit status; the PATH is searched.
# A program that cannot start, or one that ends with a status above 125, reports 125.
export fn run_program(program: String, arguments: List[String]) Int:
    if let child = spawn(
        program, arguments, stdin: Stdio.Null, stdout: Stdio.Inherit,
        stderr: Stdio.Inherit
    ):
        return status(child.wait().get(125))

    note("cannot start {program}")
    return 125

# Runs `program` and returns its standard output; empty when it cannot run or fails.
export fn capture(program: String, arguments: List[String]) String:
    if let out = run(program, arguments):
        if out.exit_code == 0: return out.stdout.decode_utf8().get("")
    return ""

# Whether `program` runs and exits zero with `arguments`.
export fn works(program: String, arguments: List[String]) Bool:
    if let out = run(program, arguments): return out.exit_code == 0

    return false

# The SHA-256 of the file at `path` as lowercase hex.
export fn file_sha256(path: String) String:
    let data = read_file(path).get()
    return hex_encode(sha256(data))

# The host triple's architecture field, as `rustc` reports it (`x86_64`, `aarch64`).
export fn rust_arch() String:
    for line in capture("rustc", ["-vV"]).split("\n"):
        if line.starts_with("host: "): return line.slice(
            6, line.length()
        ).get("").split("-")[0].clone()
    return "x86_64"

# Builds the native runtime with allocation counters (`ms-rt` feature `stats`) for the target the
# programs link against (musl on Linux, mingw-w64 on Windows) and points MS_RT_LIB at it. The caller's
# `ms` is the release build (`make build`). Returns a nonzero status when a build fails. LEAK_TARGET_DIR overrides the directory.
export fn use_stats_runtime() Int:
    let stats_target = env("LEAK_TARGET_DIR", "target/leak-stats")
    var release = "release"
    var target = ""
    let arch = rust_arch()

    if host() == "linux":
        target = "{arch}-unknown-linux-musl"
        release = "{target}/release"
        set_environment("CC_{target.replace("-", "_")}", env("CC", "cc")).get()
    else if host() == "windows":
        target = "{arch}-pc-windows-gnullvm"
        release = "{target}/release"

        let mingw = env("MS_MINGW", "target/llvm-bundle/mingw")
        set_environment(
            "CC_{target.replace("-", "_")}", "{mingw}/bin/{arch}-w64-mingw32-clang"
        ).get()

    set_environment("CARGO_TARGET_DIR", stats_target).get()

    var build = [
        "build", "--release", "--locked", "-q", "-p", "ms-native", "--features",
        "ms-rt/stats"
    ]
    if target != "": build = build.concat(["--target", target.clone()])

    var code = run_program("cargo", build)
    set_environment("CARGO_TARGET_DIR", none).get()
    if code != 0: return code

    code = run_program("cargo", ["xtask", "runtime"])
    if code != 0: return code

    let lib = canonicalize("{stats_target}/{release}/libms_native.a").get()
    set_environment("MS_RT_LIB", lib).get()
    return 0

# The ms that runs the programs under test: `MS` (resolved against `root` when relative), else
# target/release/ms.
export fn tool_ms(root: String) String:
    let named = env("MS", "")
    if named == "": return "{root}/target/release/ms{exe()}"
    if named.starts_with("/") or named.contains(":"): return named

    return "{root}/{named}{exe()}"
