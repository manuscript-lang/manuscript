import expect_equal, fail from "@std/test/test.ms"
import base64_encode, base64_decode, hex_encode from "@std/data/encoding.ms"
import (
    base64_encoded,
    base64_decoded,
    hex_encoded,
    hex_decoded
) from "@std/data/encoding_stream.ms"
import join from "@std/bytes.ms"
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

type Texts:
    parts: List[String]
    at: Int

impl Source[String] for Texts:
    var fn next() String?!:
        if self.at >= self.parts.length(): return ok(none)

        let part = self.parts[self.at].clone()
        self.at += 1
        return ok(part)

    var fn close() Unit!:
        return ok(unit)

// Splits text into pieces of `size` characters.
fn pieces(text: String, size: Int) List[String]:
    var out: List[String] = []
    var at = 0

    while at < text.length():
        var end = at + size
        if end > text.length(): end = text.length()
        out.append(text.slice(at, end).get(""))
        at = end

    return out

fn join_text(input: ReadStream[String]) String!:
    var source = input
    var out = ""

    while true:
        let next = try source.next()

        if let text = next:
            out = out.concat(text)
        else:
            break

    return ok(out)

fn join_bytes(input: ReadStream[Bytes]) Bytes!:
    var source = input
    var out: List[Bytes] = []

    while true:
        let next = try source.next()

        if let data = next:
            out.append(data)
        else:
            break

    return ok(join(out))

test "base64 encoding matches the whole-value function under every chunk size":
    let data = "hello, streams! \u{0}\u{ff}~~??".to_bytes()

    for size in 1..data.length() + 1:
        for url_safe in [false, true]:
            let got = try join_text(
                base64_encoded(chunked(data.clone(), size), url_safe)
            )
            if got != base64_encode(data.clone(), url_safe): return fail(
                "size {size} url_safe {url_safe}"
            )

test "base64 decoding matches under every text piece size":
    let data = "hello, streams! \u{0}\u{ff}~~??".to_bytes()
    let text = base64_encode(data.clone())

    for size in 1..text.length() + 1:
        let got = try join_bytes(
            base64_decoded(ReadStream[String](Texts(pieces(text, size), 0)))
        )
        if got != data: return fail("size {size}")

test "base64 decoding rejects malformed text and truncated groups":
    let bad = join_bytes(base64_decoded(ReadStream[String](Texts(["aGVs", "bG8*"], 0))))
    try expect_equal(bad.err().kind, "EBADMSG")

    let cut = join_bytes(base64_decoded(ReadStream[String](Texts(["aGVsb"], 0))))
    try expect_equal(cut.err().kind, "EBADMSG")

test "base64 decoding rejects data after padding at every chunk boundary":
    for text in ["Zg==Zg==", "Zm8=Zg==", "Zg==AAAA", "Zg==A", "Zg==="]:
        for url_safe in [false, true]:
            try expect_equal(base64_decode(text, url_safe).err().kind, "EBADMSG")

            for cut in 0..text.length() + 1:
                let left = text.slice(0, cut).get("")
                let right = text.slice(cut, text.length()).get("")
                let got = join_bytes(
                    base64_decoded(
                        ReadStream[String](
                            Texts([left, "", right], 0)
                        ),
                        url_safe
                    )
                )
                try expect_equal(got.err().kind, "EBADMSG")

test "base64 decoding permits empty chunks after terminal padding":
    for text in ["Zg==", "Zm8=", "Zm9v", ""]:
        for url_safe in [false, true]:
            for cut in 0..text.length() + 1:
                let left = text.slice(0, cut).get("")
                let right = text.slice(cut, text.length()).get("")
                let got = try join_bytes(
                    base64_decoded(
                        ReadStream[String](
                            Texts(
                                [
                                    "", left, "", right, "", ""
                                ],
                                0
                            )
                        ),
                        url_safe
                    )
                )
                try expect_equal(got, try base64_decode(text, url_safe))

test "base64 terminal padding survives a rejected read":
    var same_chunk = base64_decoded(
        ReadStream[String](Texts(["Zg==A", "", "", "AAA", "", ""], 0))
    )
    try expect_equal(same_chunk.next().err().kind, "EBADMSG")
    try expect_equal(same_chunk.next().err().kind, "EBADMSG")
    try expect_equal(try same_chunk.next(), none)

    var later_chunk = base64_decoded(
        ReadStream[String](Texts(["Zg==", "A", "", "", "AAA", "", ""], 0))
    )
    try expect_equal((try later_chunk.next()).get(), "f".to_bytes())
    try expect_equal(later_chunk.next().err().kind, "EBADMSG")
    try expect_equal(later_chunk.next().err().kind, "EBADMSG")
    try expect_equal(try later_chunk.next(), none)

test "hex steps round trip under every chunk size":
    let data = "hex \u{0}\u{ff} data".to_bytes()

    for size in 1..data.length() + 1:
        let text = try join_text(hex_encoded(chunked(data.clone(), size)))
        if text != hex_encode(data.clone()): return fail("encode size {size}")

        let back = try join_bytes(
            hex_decoded(ReadStream[String](Texts(pieces(text, size), 0)))
        )
        if back != data: return fail("decode size {size}")

test "hex decoding rejects an odd tail":
    let outcome = join_bytes(hex_decoded(ReadStream[String](Texts(["abc"], 0))))
    try expect_equal(outcome.err().kind, "EBADMSG")
