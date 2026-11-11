// conform: tags=diagnostics
// conform: phase=check
import stdin from "@std/io/io.ms"
export fn main() Int:
    number := read_number()
    var result = number + 1

    while result == 42:
        result = result + 0
    return result - 42

fn read_number() Int:
    input := stdin().read(max_bytes: 1)
    return 41
