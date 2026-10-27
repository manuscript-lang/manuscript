from "@std/bench.ms" import keep, measure
from "@std/bytes.ms" import Bytes
from "@std/collections.ms" import range
from "@std/io.ms" import IoError, ReadStream, lines, read_line

type MemoryStream:
    data: Bytes
    offset: Int

impl ReadStream for MemoryStream:
    var def read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]:
        if self.offset == self.data.length():
            return ok(none)

        var end = self.offset + max_bytes.get(65536)
        if end > self.data.length():
            end = self.data.length()

        let chunk = self.data.slice(self.offset, end).get().clone()
        self.offset = end
        return ok(chunk)

    var def close() -> Unit:
        self.offset = self.data.length()

def source_text() -> String:
    var parts: List[String] = []
    for i in range(0, 100000):
        parts.append(f"line number {i} with some padding text\n")
    return parts.join("")

bench "io.read_line_loop":
    let bytes = source_text().to_bytes()

    def work() -> Result[Unit, Error]:
        let input: ReadStream = MemoryStream(bytes.clone(), 0)
        var count = 0

        while True:
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

    def work() -> Result[Unit, Error]:
        var reader = lines(MemoryStream(bytes.clone(), 0))
        var count = 0
        for line in reader:
            count += 1
        return keep(count)

    try measure(10, work)
