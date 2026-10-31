import stdout from "@std/io.ms"

export fn main() Int:
    let text = "x".repeat(4194304).get()
    let result = text.normalize("NFC").get()
    if result != text: return 1

    let _written = stdout().write("{result.byte_length()}\n")
    return 0
