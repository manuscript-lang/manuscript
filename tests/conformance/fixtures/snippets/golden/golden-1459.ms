// conform: tags=diagnostics
// conform: phase=check
import read_line, ReadStream, stdin from "@std/io/io.ms"
fn limit() Int:
    return 1 / 0
fn probe(input: ReadStream) Bool:
    if line := read_line(input, limit()):
        return line.is_some()
    return false
export fn main() Int:
    if probe(stdin()): return 1
    return 0
