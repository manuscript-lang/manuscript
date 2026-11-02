import open, temporary, write_file from "@std/os/fs.ms"
import ReadStream, read_line from "@std/io/io.ms"
import expect_equal from "@std/test/test.ms"
import MemoryStream from "./support/streams.ms"

test "an unterminated carriage return remains line content":
    let temporary = try temporary("manuscript-line-endings-")
    let path = "{temporary.path()}/line.txt"

    for text in ["\r", "tail\r", "tail\r\r"]:
        try write_file(path, text, replace: true)

        let file = try open(path, "r", 384)
        let input = file.reader()
        try expect_equal((try read_line(input)), text)
        try expect_equal((try read_line(input)), none)

test "native and source line readers agree on endings and byte limits":
    let limits: List[Int?] = [none, 0, 1, 2, 3, 8]
    let temporary = try temporary("manuscript-line-parity-")
    let path = "{temporary.path()}/lines.txt"

    for text in ["", "a", "a\n", "a\r\n", "a\r", "\r", "\r\n", "a\nb\r", "é\r", "🙂\r\n"]:
        for limit in limits:
            try write_file(path, text, replace: true)

            let file = try open(path, "r", 384)
            let input = file.reader()
            let source: ReadStream = MemoryStream(text.to_bytes(), 0, closed: false)

            for i in 0..3:
                let actual = read_line(input, limit)
                try expect_equal(actual, read_line(source, limit))
                if actual.is_error():
                    break
