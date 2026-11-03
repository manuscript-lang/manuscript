import open, temporary, write_file from "@std/os/fs.ms"
import lines, collect from "@std/io/streams.ms"
import expect_equal from "@std/test/test.ms"
import memory from "./support/streams.ms"

test "an unterminated carriage return remains line content":
    let temporary = try temporary("manuscript-line-endings-")
    let path = "{temporary.path()}/line.txt"

    for text in ["\r", "tail\r", "tail\r\r"]:
        try write_file(path, text, replace: true)

        let file = try open(path, "r", 384)
        let found = try collect(lines(try file.reader()), none)
        try expect_equal(found, [text])

test "file and memory line readers agree on endings and byte limits":
    let limits: List[Int?] = [none, 0, 1, 2, 3, 8]
    let temporary = try temporary("manuscript-line-parity-")
    let path = "{temporary.path()}/lines.txt"

    for text in ["", "a", "a\n", "a\r\n", "a\r", "\r", "\r\n", "a\nb\r", "é\r", "🙂\r\n"]:
        for limit in limits:
            try write_file(path, text, replace: true)

            let file = try open(path, "r", 384)
            let actual = collect(lines(try file.reader(), limit), none)
            try expect_equal(actual, collect(lines(memory(text), limit), none))
