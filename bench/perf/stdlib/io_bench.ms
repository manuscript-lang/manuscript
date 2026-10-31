import keep, measure from "@std/bench.ms"
import Bytes from "@std/bytes.ms"
import IoError, ReadStream, lines, read_line from "@std/io.ms"

type MemoryStream:
    data: Bytes
    offset: Int

impl ReadStream for MemoryStream:
    var fn read(max_bytes: Optional[Int]) Result[Optional[Bytes], IoError]:
        if self.offset == self.data.length():
            return ok(none)

        var end = self.offset + max_bytes.get(65536)
        if end > self.data.length():
            end = self.data.length()

        let chunk = self.data.slice(self.offset, end).get().clone()
        self.offset = end
        return ok(chunk)

    var fn close() Unit:
        self.offset = self.data.length()

fn source_text() String:
    var parts: List[String] = []
    for i in 0..100000:
        parts.append("line number {i} with some padding text\n")
    return parts.join("")

bench "io.read_line_loop":
    let bytes = source_text().to_bytes()

    fn work() Result[Unit, Error]:
        let input: ReadStream = MemoryStream(bytes.clone(), 0)
        var count = 0

        while true:
            let next = read_line(input, none)
            if next.is_error():
                return keep(-1)
            if next.get().is_none():
                break

            count += 1

        return keep(count)

    try measure(10, work)

bench "io.lines":
    let bytes = source_text().to_bytes()

    fn work() Result[Unit, Error]:
        var reader = lines(MemoryStream(bytes.clone(), 0))
        var count = 0
        for line in reader:
            count += 1
        return keep(count)

    try measure(10, work)
