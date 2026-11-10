import OpenMode, OpenOptions, open, temporary, write_file from "@std/os/fs.ms"
import lines, collect, from_list, from_bytes from "@std/io/streams.ms"
import expect_equal from "@std/test/test.ms"
import memory from "./support/streams.ms"

test "an unterminated carriage return remains line content":
    temporary := try temporary("manuscript-line-endings-")
    path := "{temporary.path()}/line.txt"

    for text in ["\r", "tail\r", "tail\r\r"]:
        try write_file(path, text, replace: true).wait()

        file := try open(path, OpenMode.Read, OpenOptions(permissions: 384))
        found := try collect(lines(try file.reader()), none)
        try expect_equal(found, [text])

test "file and memory line readers agree on endings and byte limits":
    limits: List[Int?] = [none, 0, 1, 2, 3, 8]
    temporary := try temporary("manuscript-line-parity-")
    path := "{temporary.path()}/lines.txt"

    for text in ["", "a", "a\n", "a\r\n", "a\r", "\r", "\r\n", "a\nb\r", "é\r", "🙂\r\n"]:
        for limit in limits:
            try write_file(path, text, replace: true).wait()

            file := try open(path, OpenMode.Read, OpenOptions(permissions: 384))
            actual := collect(lines(try file.reader(), limit), none)
            try expect_equal(actual, collect(lines(memory(text), limit), none))

test "a carriage return split from its newline does not count toward the limit":
    chunks := ["abc\r".to_bytes(), "\n".to_bytes()]
    found := try collect(lines(from_list(chunks), 3), none)
    try expect_equal(found, ["abc"])

test "an unterminated carriage return counts toward the limit at the end":
    found := collect(lines(from_list(["abc\r".to_bytes()]), 3), none)
    try expect_equal(found.is_error(), true)

test "a line that is not valid UTF-8 is an error, not an empty line":
    bad := "ok\n".to_bytes().concat("\u{ff}".to_bytes().slice(0, 1).get()).concat(
        "\nnext\n".to_bytes()
    )
    found := collect(lines(from_bytes(bad)), none)
    try expect_equal(found.err().kind, "EBADMSG")

test "lines decode in place across chunks with non-ASCII text and a final unterminated line":
    var source = ""
    var expected: List[String] = []

    for i in 0..3000:
        text := "ligne {i} é日本"
        expected.append(text.clone())
        source += text
        source += if i % 2 == 0: "\r\n" else: "\n"

    expected.append("last")
    source += "last"

    found := try collect(lines(memory(source, 7)), none)
    try expect_equal(found, expected)

test "long lines cross small chunks without changing output":
    text := try "é日本".repeat(8192)

    for chunk in [1, 7, 64, 4096]:
        source := "{text}\r\nnext\n{text}"
        found := try collect(lines(from_bytes(source.to_bytes(), chunk)), none)
        try expect_equal(found, [text.clone(), "next", text.clone()])

test "empty chunks preserve pending carriage returns and byte budgets":
    for tail in ["\n", ""]:
        chunks := ["abc\r".to_bytes(), "".to_bytes(), "".to_bytes(), tail.to_bytes()]
        found := collect(lines(from_list(chunks), 3), none)

        if tail == "\n": try expect_equal(found, ok(["abc"]))
        else: try expect_equal(found.err().kind, "EOVERFLOW")
