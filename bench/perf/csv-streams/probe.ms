import Bytes from "@std/bytes.ms"
import ReadStream, Source from "@std/io/io.ms"
import csv_rows from "@std/data/csv.ms"
import monotonic from "@std/time.ms"

type Chunks:
    data: Bytes
    size: Int
    at: Int = 0

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

type Case:
    name: String
    data: Bytes
    chunk: Int
    expected: String
    operations: Int = 4
    malformed: Bool = false

fn read(item: Case) Int!:
    var rows = csv_rows(ReadStream[Bytes](Chunks(item.data.clone(), item.chunk)))
    let first = rows.next()

    if item.malformed:
        if not first.is_error(): return error(Error("expected malformed CSV"))
        if first.err().kind != "EBADMSG": return error(Error("wrong error kind"))

        return ok(item.data.length())

    let found = try first
    if found.is_none(): return error(Error("missing row"))

    let row = found.get()
    if row.length() != 1 or row[0] != item.expected: return error(Error("wrong row"))
    if (try rows.next()).is_some(): return error(Error("extra row"))

    return ok(row[0].byte_length())

fn measure(item: Case) Unit!:
    let length = if item.malformed: item.data.length() else: item.expected.byte_length()

    for sample in 0..6:
        let started = monotonic()
        var checksum = 0
        for _iteration in 0..item.operations:
            checksum += try read(item)

        let ns = monotonic().difference(started).to_nanoseconds()
        if checksum != length * item.operations: return error(Error("wrong checksum"))

        print(
            "{item.name},{item.chunk},{item.data.length()},{item.operations},{sample},{ns},{checksum}"
        )

    return ok(unit)

export fn main() Int:
    for chunk in [1, 64, 1000000]:
        for length in [4096, 8192, 16384, 32768, 65536]:
            let expected = "x".repeat(length).get()
            measure(Case("plain", "{expected}\n".to_bytes(), chunk, expected)).get()

    let quoted = "é\"日\n".repeat(2048).get()
    let encoded = "\"{quoted.replace("\"", "\"\"")}\"\r\n".to_bytes()
    for chunk in [1, 64, 1000000]:
        measure(Case("quoted", encoded.clone(), chunk, quoted.clone())).get()

    for chunk in [1, 4, 1000000]:
        for field in ["x", "a,b", "é\"日\n"]:
            let data = "\"{field.replace("\"", "\"\"")}\"\r\n".to_bytes()
            measure(Case("small-quoted", data, chunk, field.clone(), operations: 20000)).get()

        measure(Case("small-plain", "x\n".to_bytes(), chunk, "x", operations: 20000)).get()
        measure(Case("small-tail", "x".to_bytes(), chunk, "x", operations: 20000)).get()
        measure(
            Case(
                "malformed", "\"x\"bad\n".to_bytes(), chunk, "", operations: 20000,
                malformed: true
            )
        ).get()
        measure(
            Case(
                "unterminated", "\"x".to_bytes(), chunk, "", operations: 20000,
                malformed: true
            )
        ).get()

    return 0
