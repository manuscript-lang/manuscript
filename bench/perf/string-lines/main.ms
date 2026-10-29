import stdout from "@std/io.ms"
import clock from "@std/time.ms"

fn measure(name: String, text: String, expected: Int, iterations: Int) Int:
    var checksum = 0
    let started = clock().now()
    for iteration in 0..iterations:
        let lines = text.lines()
        checksum += lines.length() * 17
        for line in lines:
            checksum += line.byte_length()
    let elapsed = clock().now().difference(started).to_nanoseconds()
    if checksum != expected * iterations:
        return 1
    let _written = stdout().write("{name},{text.byte_length()},{iterations},{elapsed},{checksum}\n")
    return 0

export fn main() Int:
    let _header = stdout().write("case,input_bytes,iterations,elapsed_ns,checksum\n")
    if measure("empty", "", 0, 100000) != 0: return 1
    if measure("tiny", "a\nb\n", 36, 100000) != 0: return 1
    if measure("short_unterminated", "hello", 22, 100000) != 0: return 1
    if measure("empty_lines", "\n\n\n\n", 68, 100000) != 0: return 1
    for width in [7, 8, 15, 16, 31, 32, 128, 1024, 8192, 65536]:
        let count = 1048576 / (width + 1)
        let text = ("x".repeat(width).get() + "\n").repeat(count).get()
        if measure("lf_{width}", text, (width + 17) * count, 16) != 0: return 1
    let unicode = ("é日😀".repeat(1000).get() + "\r\n").repeat(128).get()
    if measure("unicode_crlf", unicode, (9000 + 17) * 128, 16) != 0: return 1
    let no_newline = "x".repeat(1048576).get()
    if measure("no_newline", no_newline, 1048576 + 17, 16) != 0: return 1
    return 0
