import expect_equal, fail from "@std/test/test.ms"
import (
    multipart_parts,
    parse_multipart,
    encode_multipart,
    form_part,
    Part
) from "@std/net/mime.ms"
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

fn read_parts(body: Bytes, size: Int, max_part_bytes: Int? = none) List[Part]!:
    var parts = multipart_parts(chunked(body, size), "XyZ", max_part_bytes)
    var out: List[Part] = []

    while true:
        let next = try parts.read().wait()

        if let part = next:
            out.append(part)
        else:
            break

    return ok(out)

fn sample() Bytes:
    return encode_multipart(
        [
            form_part("title", "hello".to_bytes()),
            form_part(
                "file", "line1\r\nline2\r\n--not-a-delimiter".to_bytes(),
                filename: "a.txt", content_type: "text/plain"
            ),
            form_part("empty", "".to_bytes())
        ],
        "XyZ"
    )

test "parts match parse_multipart under every chunk size":
    let body = "preamble ignored\r\n".to_bytes().concat(sample())
    let expected = try parse_multipart(body.clone(), "XyZ")
    for size in 1..body.length() + 1:
        if (try read_parts(body.clone(), size)) != expected: return fail(
            "chunk size {size}"
        )
    try expect_equal(expected.length(), 3)
    try expect_equal(expected[1].filename, "a.txt")

test "a body without the closing delimiter is InvalidData":
    let body = "--XyZ\r\nContent-Disposition: form-data; name=a\r\n\r\nvalue".to_bytes()
    let outcome = read_parts(body, 5)
    try expect_equal(outcome.err().kind, "EBADMSG")

test "the part budget reports LimitExceeded":
    let big = encode_multipart(
        [form_part("f", "x".repeat(500).get("").to_bytes())], "XyZ"
    )
    let outcome = read_parts(big.clone(), 64, 100)
    try expect_equal(outcome.err().kind, "EOVERFLOW")
    try expect_equal((try read_parts(big, 64, 1000)).length(), 1)
