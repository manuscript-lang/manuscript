import Bytes from "@std/bytes.ms"
import Sink, WriteStream, stdout, writer from "@std/io/io.ms"
import Promise from "@std/concurrency/promise.ms"
import json_writer from "@std/data/json.ms"
import csv_writer, CsvOptions from "@std/data/csv.ms"
import compile, render_to, to_data from "@std/text/template.ms"

type Point:
    x: Int
    label: String

// Prints the bytes it is given, so the output shows what the format writers produced.
type Echo:
    out: WriteStream[String]

impl Sink[Bytes] for Echo:
    var fn put(value: Bytes) Unit!:
        return self.out.write(value.decode_utf8().get(""))

    var fn drain() Promise[Unit]:
        return self.out.flush()

    fn buffered() Int:
        return self.out.buffered()

    var fn close() Unit!:
        return ok(unit)

fn echo() WriteStream[Bytes]:
    return writer[Bytes](Echo(stdout()))

fn run() Unit!:
    var points = json_writer[Point](echo())
    try points.write(Point(1, "a \"quoted\" label"))
    try points.write(Point(2, "é😀"))

    var rows = csv_writer(echo(), CsvOptions(delimiter: ";"))
    try rows.write(["id", "name"])
    try rows.write(["1", "needs;quote"])
    try rows.write(["2", "multi\nline"])

    let page = try compile(
        "\{\{ for p in points \}\}\{\{ p.x \}\}=\{\{ p.label \}\}\n\{\{ end \}\}"
    )
    let data = try to_data({"points": [Point(1, "one"), Point(2, "two")]})
    var out = stdout()
    try render_to(page, data, var out)
    return ok(unit)

export fn main() Int:
    let result = run()
    if result.is_error(): return 1

    return 0
