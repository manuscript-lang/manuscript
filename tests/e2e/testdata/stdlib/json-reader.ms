import expect_equal, expect_false, fail from "@std/test/test.ms"
import json_reader, stringify, JsonValue, JsonOptions from "@std/data/json.ms"
import Bytes from "@std/bytes.ms"
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

// Reads every value as text, or the first error.
fn decode(input: Bytes, size: Int, limits: JsonOptions = JsonOptions()) List[String]!:
    var values = json_reader[JsonValue](chunked(input, size), limits)
    var out: List[String] = []

    while true:
        let next = try values.next()

        if let item = next:
            out.append(try stringify(item))
        else:
            break

    return ok(out)

test "values split at every chunk size are preserved":
    let source = "\{\"a\":\"é🙂\\u00e9\\\"x\}\{\",\"n\":9007199254740993,\"l\":[1,[true,null]]\}\n\"s\"[1]\{\"b\":2\}  42"
    let expected = [
        "\{\"a\":\"é🙂é\\\"x\}\{\",\"n\":9007199254740993,\"l\":[1,[true,null]]\}",
        "\"s\"", "[1]", "\{\"b\":2\}", "42"
    ]
    let input = source.to_bytes()
    for size in 1..input.length() + 1:
        if (try decode(input.clone(), size)) != expected: return fail(
            "chunk size {size}"
        )

test "typed values decode as parse does":
    var numbers = json_reader[Int](chunked("1 2\n3".to_bytes(), 2))
    var sum = 0

    while true:
        let next = try numbers.next()

        if let n = next:
            sum += n
        else:
            break

    try expect_equal(sum, 6)

test "truncated and malformed input fails the read":
    for text in ["\{\"a\":[1", "\"open", "x", "[1]]", "truex y"]:
        let outcome = decode("{text} ".to_bytes(), 3)

        if text == "\{\"a\":[1" or text == "\"open":
            let cut = decode(text.to_bytes(), 3)
            try expect_equal(cut.err().kind, "EBADMSG")
        else:
            try expect_equal(outcome.err().kind, "EBADMSG")

test "invalid UTF-8 inside a value is InvalidData":
    let bad = "\"a\"".to_bytes()
    let outcome = decode(bad.with_value(1, 255), 2)
    try expect_equal(outcome.err().kind, "EBADMSG")

test "per-value budgets report LimitExceeded":
    try expect_equal(
        (try decode("[1,2]".to_bytes(), 2, JsonOptions(max_bytes: 5))), ["[1,2]"]
    )

    let wide = decode("[1,2,3]".to_bytes(), 2, JsonOptions(max_bytes: 5))
    try expect_equal(wide.err().kind, "EOVERFLOW")

    let deep = decode("[[[".to_bytes(), 2, JsonOptions(max_depth: 2))
    try expect_equal(deep.err().kind, "EOVERFLOW")
