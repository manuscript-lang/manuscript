import read_all, read_line, stdin, stdout from "@std/io.ms"

# Each `stdin()` call reads where the previous handle stopped, read-ahead included.
export fn main() Int:
    var n = 0

    while n < 3:
        let next = read_line(input: stdin(), max_bytes: 100).get(none)
        if next.is_none():
            return 1

        stdout().write("{n}:{next.get()}\n").get()
        n += 1

    let rest = read_all(input: stdin()).get()
    stdout().write("rest:{rest.decode_utf8().get("")}").get()
    return 0
