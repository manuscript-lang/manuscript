// conform: tags=diagnostics
// conform: phase=check
import arguments from "@std/os/process.ms"
import stdout, stderr from "@std/io/io.ms"

export fn main() Int:
    args := arguments()
    if args.length() > 0 and args[0] == "binary":
        _raw := stdout().write_bytes(data: "x".to_bytes().with_value(index: 0, value: 255))
        return 0
    _out := stdout().write(data: "stdout\n")
    _err := stderr().write(data: "stderr\n")
    var index = 0
    while index < args.length():
        _arg := stdout().write(data: "arg={args[index]}\n")
        index = index + 1
    if args.length() > 0 and args[0] == "fail":
        return 23
    return 0
