import expect_equal, fail from "@std/test/test.ms"
import csv_rows, parse, CsvOptions from "@std/data/csv.ms"
import Bytes, BytesBuilder from "@std/bytes.ms"
import ReadStream, Source from "@std/io/io.ms"

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
        let next = try rows.next()

        if let row = next:
            out.append(row)
        else:
            break

    return ok(out)

test "rows match parse under every chunk size":
    let text = "a,b,c\r\n1,\"x,y\",3\n\n\"multi\nline \"\"q\"\"\",é,😀\n\"\"\nlast,,"
    let expected = try parse(text)
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
    try expect_equal(outcome.err().kind, "EBADMSG")

test "a quote inside an unquoted cell is InvalidData":
    let outcome = read_rows("a,b\"c\n", 4)
    try expect_equal(outcome.err().kind, "EBADMSG")

test "the record budget reports LimitExceeded":
    let outcome = read_rows("a,\"never closed", 3, CsvOptions(), 8)
    try expect_equal(outcome.err().kind, "EOVERFLOW")
    try expect_equal(
        try read_rows("ab,cd\nef,gh\n", 3, CsvOptions(), 8),
        [["ab", "cd"], ["ef", "gh"]]
    )

test "the record budget does not depend on where chunks end":
    for size in 1..12:
        let long = read_rows("abcdefghij\n", size, CsvOptions(), 4)
        try expect_equal(long.err().kind, "EOVERFLOW")

        let many = read_rows("ab\ncdefghij\nkl\n", size, CsvOptions(), 4)
        try expect_equal(many.err().kind, "EOVERFLOW")

        let quoted = read_rows("\"a\nb\nc\nd\",x\n", size, CsvOptions(), 4)
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

    let block = bad.build()
    var tail = BytesBuilder()
    tail.append(255)

    let unterminated = tail.build()
    var truncated = BytesBuilder()
    truncated.append_bytes("a,".to_bytes())
    truncated.append(195)
    truncated.append(10)

    let cut = truncated.build()

    for size in 1..6:
        try expect_equal(read_raw(block.clone(), size).err().kind, "EBADMSG")
        try expect_equal(read_raw(unterminated.clone(), size).err().kind, "EBADMSG")
        try expect_equal(read_raw(cut.clone(), size).err().kind, "EBADMSG")

    for size in 1..8:
        try expect_equal(try read_rows("a,é,😀\n", size), [["a", "é", "😀"]])
