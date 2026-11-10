// Build once with each compiler, then pass one case name to each executable.
import (
    posix, win32 from "@std/os/path.ms",
    arguments from "@std/os/env.ms",
    monotonic from "@std/time.ms",
    print from "@std/core.ms",
)

fn work(mode: String, path: String) String:
    if mode.starts_with("basename"): return posix().basename(path)
    if mode.starts_with("dirname"): return posix().dirname(path)
    if mode.starts_with("extension"): return posix().extension(path)
    if mode.starts_with("join"): return win32().join([path.clone(), "服务器/共享"])

    return win32().parse(path).root

export fn main() Int:
    let mode = arguments().get(0, "basename_plain")
    let many = "/".repeat(32000).get("")
    var inputs = ["folder/file.txt", "folder/other.txt"]
    if mode == "basename_slash": inputs = ["folder/file.txt/", "folder/other.txt/"]
    if mode == "basename_unicode": inputs = ["目录/文件.txt/", "目录/另一份.txt/"]
    if mode == "basename_many": inputs = ["é{many}"]
    if mode == "dirname_many": inputs = ["/目录/é.txt{many}"]
    if mode == "extension_many": inputs = ["目录/é.txt{many}"]
    if mode == "unc_plain": inputs = ["//server/share/file", "//host/disk/another"]
    if mode == "unc_unicode": inputs = ["//服务器/共享/file", "//主机/磁盘/another"]
    if mode == "unc_clean_long": inputs = [
        "//{"server".repeat(170).get("")}/share/file"
    ]
    if mode == "unc_leading_many": inputs = ["//{many}服务器/share/a"]
    if mode == "unc_share_many": inputs = ["//server/{many}共享/a"]
    if mode == "join_many": inputs = [many.clone()]

    let repeats = if mode.ends_with("_many"): 10 else: 200000
    var checksum = 0
    let start = monotonic()
    for index in 0..repeats:
        checksum += work(mode, inputs[index % inputs.length()]).byte_length()
    print("{monotonic().difference(start).to_nanoseconds()} {checksum}")
    return 0
