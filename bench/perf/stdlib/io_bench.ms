import from_list, from_bytes, fold, lines, map from "@std/io/streams.ms"
import keep, measure from "@std/test/bench.ms"
import Bytes from "@std/bytes.ms"
import Source, ReadStream from "@std/io/io.ms"

type MemorySource:
    data: Bytes
    offset: Int

impl Source[Bytes] for MemorySource:
    var fn next() Bytes?!:
        if self.offset == self.data.length():
            return ok(none)

        var end = self.offset + 65536
        if end > self.data.length():
            end = self.data.length()

        let chunk = self.data.slice(self.offset, end).get().clone()
        self.offset = end
        return ok(chunk)

    var fn close() Unit!:
        self.offset = self.data.length()
        return ok(unit)

fn source_text() String:
    var parts: List[String] = []
    for i in 0..100000:
        parts.append("line number {i} with some padding text\n")
    return parts.join("")

bench "io.lines":
    let bytes = source_text().to_bytes()

    fn work() Result[Unit, Error]:
        var reader = lines(ReadStream[Bytes](MemorySource(bytes.clone(), 0)))
        var count = 0

        while true:
            let next = reader.next()
            if next.is_error():
                return keep(-1)
            if next.get().is_none():
                break

            count += 1

        return keep(count)

    try measure(10, work)

fn counted(n: Int) List[Int]:
    var xs: List[Int] = []
    for i in 0..n:
        xs.append(i)
    return xs

fn plus(x: Int) Int:
    return x + 1

bench "io.stages.map3_fold":
    let xs = counted(200000)

    fn work() Result[Unit, Error]:
        let stream = map(map(map(from_list(xs.clone()), plus), plus), plus)
        let total = try fold(stream, 0, fn(a: Int, b: Int) Int: return a + b)
        return keep(total)

    try measure(10, work)

bench "io.lines long fragmented":
    let text = try "x".repeat(262144)
    let data = "{text}\n".to_bytes()

    fn work() Unit!:
        var input = lines(from_bytes(data.clone(), 64))
        let result = try input.next()
        try input.close()
        return keep(result.get("").byte_length())

    try measure(1, work)
