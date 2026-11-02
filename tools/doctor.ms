# Reports build prerequisites without downloading or changing the checkout (`make doctor`).
# Usage: ms run tools/doctor.ms
import env, host, works, capture from "./lib.ms"
import read_file from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"

fn say(ok: Bool, ok_text: String, missing_text: String) Bool:
    if ok: stdout().write("OK      {ok_text}\n").get()
    else: stdout().write("MISSING {missing_text}\n").get()

    return ok

# Whether `version` ("0.146.7") is at least 0.146.7.
fn hugo_new_enough(version: String) Bool:
    let parts = version.split("-")[0].split("+")[0].split(".")
    if parts.length() < 3: return false

    let major = parts[0].parse_int().get(0)
    let minor = parts[1].parse_int().get(0)
    let patch = parts[2].parse_int().get(0)
    return major > 0 or minor > 146 or (minor == 146 and patch >= 7)

export fn main() Int:
    var failed = 0
    for command in ["git", "tar"]:
        if not say(works(command, ["--version"]), command, command): failed += 1

    let expected_node = read_file(".node-version").get().decode_utf8().get("").trim()
    let node = capture("node", ["--version"]).trim()
    if not say(
        node == "v{expected_node}", "Node {expected_node}",
        "Node {expected_node} (install the version in .node-version)"
    ): failed += 1
    if not say(
        works("cargo", ["--version"]), "cargo",
        "cargo (install rustup; rust-toolchain.toml pins the toolchain)"
    ): failed += 1
    if not say(
        works("cargo", ["nextest", "--version"]), "cargo-nextest",
        "cargo-nextest (cargo install cargo-nextest --locked)"
    ): failed += 1

    let hugo = env("HUGO", "hugo")
    let hugo_output = capture(hugo, ["version"])
    var hugo_ok = false
    let fields = hugo_output.split(" ")
    if hugo_output.contains("extended") and fields.length() > 1:
        hugo_ok = hugo_new_enough(fields[1].replace("v", ""))

    if hugo_ok: stdout().write(hugo_output).get()
    else:
        stdout().write("MISSING Hugo Extended 0.146.7 or newer (book checks)\n").get()
        failed += 1

    if host() == "windows":
        if not say(works("7z", ["i"]), "7z (packaging)", "7z (packaging)"): failed += 1
    else:
        if not say(
            works("cc", ["--version"]),
            "C compiler (building ms from source; running ms needs none on Linux)",
            "C compiler (building ms from source: ring)"
        ): failed += 1

    if failed > 0: return 1

    return 0
