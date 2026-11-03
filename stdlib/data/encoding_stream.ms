import Bytes, join from "@std/bytes.ms"
import ReadStream, Transform, through from "@std/io/stream.ms"
import base64_encode, base64_decode, hex_encode, hex_decode from "@std/data/encoding.ms"

// Stream steps for `@std/data/encoding.ms`, in their own module because the streams depend on `@std/bytes.ms`,
// which `encoding.ms` must not import.
// Each step carries only the few bytes or characters that do not yet fill a group.

// Encodes bytes in groups of three, so a chunk boundary never splits a Base64 group.
type Base64Encoding:
    url_safe: Bool
    tail: Bytes

impl Transform[Bytes, String] for Base64Encoding:
    var fn feed(value: Bytes) List[String]!:
        let data = self.tail.concat(value)
        let whole = data.length() - data.length() % 3
        self.tail = try data.slice(whole, data.length())
        if whole == 0: return ok(List[String]())
        return ok([base64_encode(try data.slice(0, whole), self.url_safe)])

    var fn finish() List[String]!:
        if self.tail.is_empty(): return ok(List[String]())
        let last = self.tail.clone()
        self.tail = join([])
        return ok([base64_encode(last, self.url_safe)])

// Encodes a byte stream as Base64 text chunks that concatenate to the whole encoding, with padding at the end.
// Set `url_safe: true` for the URL-safe alphabet. Closing the result closes `input`.
export fn base64_encoded(input: ReadStream[Bytes], url_safe: Bool = false) ReadStream[String]:
    return through[Bytes, String](input, Base64Encoding(url_safe: url_safe, tail: join([])))

// Decodes Base64 text in groups of four characters, so a chunk boundary never splits a group.
type Base64Decoding:
    url_safe: Bool
    tail: String

impl Transform[String, Bytes] for Base64Decoding:
    var fn feed(value: String) List[Bytes]!:
        let text = self.tail.concat(value)
        let whole = text.length() - text.length() % 4
        self.tail = text.slice(whole, text.length()).get("")
        if whole == 0: return ok(List[Bytes]())
        return ok([try base64_decode(text.slice(0, whole).get(""), self.url_safe, none)])

    var fn finish() List[Bytes]!:
        let last = self.tail.clone()
        self.tail = ""
        if last == "": return ok(List[Bytes]())
        return ok([try base64_decode(last, self.url_safe, none)])

// Decodes Base64 text chunks into bytes. Malformed text fails the read with `InvalidData`; text that ends
// inside a group fails at the end of the stream. Closing the result closes `input`.
export fn base64_decoded(input: ReadStream[String], url_safe: Bool = false) ReadStream[Bytes]:
    return through[String, Bytes](input, Base64Decoding(url_safe: url_safe, tail: ""))

type HexEncoding:
    unused: Int

impl Transform[Bytes, String] for HexEncoding:
    var fn feed(value: Bytes) List[String]!:
        return ok([hex_encode(value)])

    var fn finish() List[String]!:
        return ok(List[String]())

// Encodes a byte stream as lowercase hexadecimal text chunks. Closing the result closes `input`.
export fn hex_encoded(input: ReadStream[Bytes]) ReadStream[String]:
    return through[Bytes, String](input, HexEncoding(0))

// Decodes hexadecimal text in pairs, so a chunk boundary never splits a byte.
type HexDecoding:
    tail: String

impl Transform[String, Bytes] for HexDecoding:
    var fn feed(value: String) List[Bytes]!:
        let text = self.tail.concat(value)
        let whole = text.length() - text.length() % 2
        self.tail = text.slice(whole, text.length()).get("")
        if whole == 0: return ok(List[Bytes]())
        return ok([try hex_decode(text.slice(0, whole).get(""), none)])

    var fn finish() List[Bytes]!:
        let last = self.tail.clone()
        self.tail = ""
        if last == "": return ok(List[Bytes]())
        return ok([try hex_decode(last, none)])

// Decodes hexadecimal text chunks into bytes. Malformed text, or text that ends inside a pair, fails the
// read with `InvalidData`. Closing the result closes `input`.
export fn hex_decoded(input: ReadStream[String]) ReadStream[Bytes]:
    return through[String, Bytes](input, HexDecoding(tail: ""))
