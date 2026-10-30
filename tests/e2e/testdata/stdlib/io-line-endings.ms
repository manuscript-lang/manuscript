import filesystem from "@std/fs.ms"
import ReadStream, read_line from "@std/io.ms"
import expect_equal from "@std/test.ms"
import MemoryStream from "./support/streams.ms"

test "an unterminated carriage return remains line content":
    let fs = filesystem()
    let temporary = try fs.temporary("manuscript-line-endings-")
    let path = "{temporary.path()}/line.txt"

    for text in ["\r", "tail\r", "tail\r\r"]:
        try fs.write_file(path, text, replace: true)

        let file = try fs.open(path, "r", 384)
        let input = file.reader()
        try expect_equal((try read_line(input)), some(text))
        try expect_equal((try read_line(input)), none)

test "native and source line readers agree on endings and byte limits":
    let fs = filesystem()
    let limits: List[Optional[Int]] = [
        none, some(0), some(1), some(2), some(3), some(8)
    ]
    let temporary = try fs.temporary("manuscript-line-parity-")
    let path = "{temporary.path()}/lines.txt"

    for text in ["", "a", "a\n", "a\r\n", "a\r", "\r", "\r\n", "a\nb\r", "é\r", "🙂\r\n"]:
        for limit in limits:
            try fs.write_file(path, text, replace: true)

            let file = try fs.open(path, "r", 384)
            let input = file.reader()
            let source: ReadStream = MemoryStream(text.to_bytes(), 0, closed: false)

            for i in 0..3:
                let actual = read_line(input, limit)
                try expect_equal(actual, read_line(source, limit))
                if actual.is_error():
                    break
