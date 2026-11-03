import Bytes from "@std/bytes.ms"
import ReadStream, WriteStream, Transform, through, stream, Source from "@std/io/io.ms"

// Steps for streams. Each takes its input first, so a pipeline is the `|` operator.

// Lines of bytes, without their `\n` or `\r\n`, cut only at line ends; the unterminated last line comes at the end.
type LineSplitter:
    tail: Bytes?

impl LineSplitter:
    // The held tail followed by `chunk`.
    var fn joined(chunk: Bytes) Bytes:
        if let held = self.tail:
            return held.concat(chunk)
        return chunk.clone()

impl Transform[Bytes, String] for LineSplitter:
    var fn feed(value: Bytes) List[String]!:
        var out: List[String] = []
        let data = self.joined(value)
        var start = 0
        while true:
            let end = data.index_of_byte(10, start)
            if end.is_none():
                break
            var stop = end.get()
            if stop > start and data.get(stop - 1, 0) == 13:
                stop -= 1
            let line = try data.slice(start, stop)
            out.append(line.decode_utf8().get(""))
            start = end.get() + 1
        if start < data.length():
            self.tail = try data.slice(start, data.length())
        else:
            self.tail = none
        return ok(out)

    var fn finish() List[String]!:
        var out: List[String] = []
        if let held = self.tail:
            out.append(held.decode_utf8().get(""))
            self.tail = none
        return ok(out)

export fn lines(input: ReadStream[Bytes]) ReadStream[String]:
    return through[Bytes, String](input, LineSplitter(none))

