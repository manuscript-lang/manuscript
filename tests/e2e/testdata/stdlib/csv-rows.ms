import expect_equal, fail from "@std/test/test.ms"
import csv_rows, parse, CsvOptions from "@std/data/csv.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import ReadStream, Source from "@std/io/io.ms"
import from_list, collect from "@std/io/streams.ms"

// Hands out the chunks in order, then ends.
type Chunks:
    data: Bytes
    size: Int
    at: Int

impl Source[Bytes] for Chunks:
    var fn next() Bytes?!:
        if self.at >= self.data.length(): return ok(none)

        var end = self.at + self.size
        if end > self.data.length(): end = self.data.length()

        piece := try self.data.slice(self.at, end)
        self.at = end
        return ok(piece)

    var fn close() Unit!:
        return ok(unit)

fn chunked(data: Bytes, size: Int) ReadStream[Bytes]:
    return ReadStream[Bytes](Chunks(data, size, 0))

fn read_rows(
    text: String,
    size: Int,
    options: CsvOptions = CsvOptions(),
    max_record_bytes: Int? = none
) List[List[String]]!:
    return read_raw(text.to_bytes(), size, options, max_record_bytes)

fn read_raw(
    data: Bytes,
    size: Int,
    options: CsvOptions = CsvOptions(),
    max_record_bytes: Int? = none
) List[List[String]]!:
    var rows = csv_rows(chunked(data, size), options, max_record_bytes)
    var out: List[List[String]] = []

    while true:
        next := try rows.next()

        if row := next:
            out.append(row)
        else:
            break

    return ok(out)

test "rows match parse under every chunk size":
    text := "a,b,c\r\n1,\"x,y\",3\n\n\"multi\nline \"\"q\"\"\",é,😀\n\"\"\nlast,,"
    expected := try parse(text)
    for size in 1..text.to_bytes().length() + 1:
        if (try read_rows(text, size)) != expected: return fail("chunk size {size}")

test "a final record without a line end is read at the end":
    try expect_equal(try read_rows("a,b\nc,d", 3), [["a", "b"], ["c", "d"]])

test "large fragmented records preserve rows and exact record budgets":
    field := try "é\"日\n".repeat(1024)
    encoded := "\"{field.replace("\"", "\"\"")}\",tail\r"
    text := "first,row\n{encoded}\nlast,row"
    expected := [["first", "row"], [field, "tail"], ["last", "row"]]
    limit := encoded.byte_length()

    for size in [1, 2, 7, 64, 4096, text.byte_length()]:
        try expect_equal(try read_rows(text, size, max_record_bytes: limit), expected)
        try expect_equal(
            read_rows(text, size, max_record_bytes: limit - 1).err().kind, "EOVERFLOW"
        )

    var chunks: List[Bytes] = ["".to_bytes()]

    for byte in "a,\"é\"\r\nb,c\nlast,row".to_bytes().values():
        var chunk = BytesBuilder()
        chunk.append(byte)
        chunks.append(chunk.build())
        chunks.append("".to_bytes())

    from_list(chunks) | csv_rows | try collect(none)
        | try expect_equal([["a", "é"], ["b", "c"], ["last", "row"]])

test "options apply":
    semicolons := CsvOptions(delimiter: ";")
    try expect_equal(
        try read_rows("a;b\n\"c;d\";e\n", 2, semicolons), [["a", "b"], ["c;d", "e"]]
    )

test "empty CSV streams reject invalid options":
    invalid: List[List[String]]! = error(Error("CSV: invalid input", kind: "EINVAL"))

    for options in [
        CsvOptions(delimiter: ""), CsvOptions(delimiter: "::"),
        CsvOptions(delimiter: "\""), CsvOptions(delimiter: "\n"),
        CsvOptions(delimiter: "é"), CsvOptions(line_ending: "\r")
    ]:
        for text in ["", "a", "a\n"]:
            try expect_equal(read_rows(text, 1, options.clone()), invalid)

        empty_chunks := from_list(["".to_bytes(), "".to_bytes()])
        try expect_equal(
            empty_chunks | csv_rows(options.clone()) | collect(none), invalid
        )

    no_rows: List[List[String]] = []
    try expect_equal(try read_rows("", 1), no_rows)
    try expect_equal(
        try read_rows("", 1, CsvOptions(delimiter: ";", line_ending: "\r\n")), no_rows
    )

    empty_chunks := from_list(["".to_bytes(), "".to_bytes()])
    empty_chunks | csv_rows | try collect(none) | try expect_equal(no_rows)

test "an unterminated quote is InvalidData at the end":
    outcome := read_rows("a,\"open\nmore", 4)
    try expect_equal(outcome.err().kind, "EBADMSG")

test "a quote inside an unquoted cell is InvalidData":
    outcome := read_rows("a,b\"c\n", 4)
    try expect_equal(outcome.err().kind, "EBADMSG")

test "the record budget reports LimitExceeded":
    outcome := read_rows("a,\"never closed", 3, CsvOptions(), 8)
    try expect_equal(outcome.err().kind, "EOVERFLOW")
    try expect_equal(
        try read_rows("ab,cd\nef,gh\n", 3, CsvOptions(), 8),
        [["ab", "cd"], ["ef", "gh"]]
    )

test "continued reads after a record limit error keep only the consumed tail":
    for chunks in [
        ["ab", "cd\n", "x\n"], ["ab", "cd\nx", "\n"], ["ab", "cd\n\"", "x\"\n"]
    ]:
        var data: List[Bytes] = []
        for chunk in chunks:
            data.append(chunk.to_bytes())

        var rows = csv_rows(from_list(data), max_record_bytes: 3)
        try expect_equal(rows.next().err().kind, "EOVERFLOW")
        try expect_equal((try rows.next()).get(), ["x"])
        try expect_equal((try rows.next()).is_none(), true)

    input := from_list(
        ["ab".to_bytes(), "cd".to_bytes(), "\n".to_bytes(), "x\n".to_bytes()]
    )
    var rows = csv_rows(input, max_record_bytes: 3)
    try expect_equal(rows.next().err().kind, "EOVERFLOW")
    try expect_equal(rows.next().err().kind, "EOVERFLOW")
    try expect_equal((try rows.next()).get(), ["x"])
    try expect_equal((try rows.next()).is_none(), true)

test "the record budget does not depend on where chunks end":
    for size in 1..12:
        long := read_rows("abcdefghij\n", size, CsvOptions(), 4)
        try expect_equal(long.err().kind, "EOVERFLOW")

        many := read_rows("ab\ncdefghij\nkl\n", size, CsvOptions(), 4)
        try expect_equal(many.err().kind, "EOVERFLOW")

        quoted := read_rows("\"a\nb\nc\nd\",x\n", size, CsvOptions(), 4)
        try expect_equal(quoted.err().kind, "EOVERFLOW")
        try expect_equal(
            try read_rows("abcd\nefgh\n", size, CsvOptions(), 4), [["abcd"], ["efgh"]]
        )
        try expect_equal(try read_rows("abcd\r\n", size, CsvOptions(), 5), [["abcd"]])

test "malformed UTF-8 is InvalidData beside valid rows and a split scalar is not":
    var bad = BytesBuilder()
    bad.append_bytes("ok\n".to_bytes())
    bad.append(255)
    bad.append(10)

    block := bad.build()
    var tail = BytesBuilder()
    tail.append(255)

    unterminated := tail.build()
    var truncated = BytesBuilder()
    truncated.append_bytes("a,".to_bytes())
    truncated.append(195)
    truncated.append(10)

    cut := truncated.build()

    for size in 1..6:
        try expect_equal(read_raw(block.clone(), size).err().kind, "EBADMSG")
        try expect_equal(read_raw(unterminated.clone(), size).err().kind, "EBADMSG")
        try expect_equal(read_raw(cut.clone(), size).err().kind, "EBADMSG")

    for size in 1..8:
        try expect_equal(try read_rows("a,é,😀\n", size), [["a", "é", "😀"]])

test "row and cell budgets bound parse only, never depending on chunk size":
    limits := CsvOptions(max_rows: 1, max_cells: 1)
    for size in 1..5:
        try expect_equal(try read_rows("a\nb\n", size, limits.clone()), [["a"], ["b"]])
    try expect_equal(parse("a\nb\n", limits).is_error(), true)

// The rows joined for comparison, or the error kind.
fn csv_outcome(result: List[List[String]]!) String:
    if result.is_error(): return result.err().kind.get("none")

    var text = "ok"

    for row in result.get():
        text += " ["
        for cell in row:
            text += "<{cell}>"
        text += "]"

    return text

test "rows and parse agree on malformed and odd inputs under every chunk size":
    inputs := [
        "", "\n", "\r\n", "\r", "a", "a\r", "a\rb", "a\r\n\r\nb", "\"", "\"a", "\"a\"",
        "\"a\"\"", "\"a\"b", "a\"b", "a,\"b\"c,d", "\"a\n\"\"\n", ",,\n,,",
        "a,b\r\nc\n", "\"\"\"\"", "x,\"y\r\nz\",w\r\n", "é,\"😀\"\n"
    ]

    for text in inputs:
        expected := csv_outcome(parse(text))

        for size in 1..text.to_bytes().length() + 2:
            got := csv_outcome(read_rows(text, size))
            if got != expected: return fail(
                "{text.to_bytes().length()} bytes, chunk {size}: parse {expected}, stream {got}"
            )
