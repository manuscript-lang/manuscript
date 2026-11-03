import expect_equal, fail from "@std/test/test.ms"
import csv_rows, parse, CsvOptions from "@std/data/csv.ms"
import Bytes from "@std/bytes.ms"
import ReadStream, Source, stream from "@std/io/io.ms"

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

        let piece = try self.data.slice(self.at, end)
        self.at = end
        return ok(piece)

    var fn close() Unit!:
        return ok(unit)

fn chunked(data: Bytes, size: Int) ReadStream[Bytes]:
    return stream[Bytes](Chunks(data, size, 0))

fn read_rows(
    text: String,
    size: Int,
    options: CsvOptions = CsvOptions(),
    max_record_bytes: Int? = none
) List[List[String]]!:
    var rows = csv_rows(chunked(text.to_bytes(), size), options, max_record_bytes)
    var out: List[List[String]] = []

    while true:
        let next = try rows.read().wait()

        if let row = next:
            out.append(row)
        else:
            break

    return ok(out)

test "rows match parse under every chunk size":
    let text = "a,b,c\r\n1,\"x,y\",3\n\n\"multi\nline \"\"q\"\"\",é,😀\n\"\"\nlast,,"
    let expected = try parse(text, CsvOptions(), none, none)
    for size in 1..text.to_bytes().length() + 1:
        if (try read_rows(text, size)) != expected: return fail("chunk size {size}")

test "a final record without a line end is read at the end":
    try expect_equal(try read_rows("a,b\nc,d", 3), [["a", "b"], ["c", "d"]])

test "options apply":
    let semicolons = CsvOptions(delimiter: ";")
    try expect_equal(
        try read_rows("a;b\n\"c;d\";e\n", 2, semicolons), [["a", "b"], ["c;d", "e"]]
    )

test "an unterminated quote is InvalidData at the end":
    let outcome = read_rows("a,\"open\nmore", 4)
    try expect_equal(outcome.err().kind, ErrorCategory.InvalidData)

test "a quote inside an unquoted cell is InvalidData":
    let outcome = read_rows("a,b\"c\n", 4)
    try expect_equal(outcome.err().kind, ErrorCategory.InvalidData)

test "the record budget reports LimitExceeded":
    let outcome = read_rows("a,\"never closed", 3, CsvOptions(), 8)
    try expect_equal(outcome.err().kind, ErrorCategory.LimitExceeded)
    try expect_equal(
        try read_rows("ab,cd\nef,gh\n", 3, CsvOptions(), 8),
        [["ab", "cd"], ["ef", "gh"]]
    )
