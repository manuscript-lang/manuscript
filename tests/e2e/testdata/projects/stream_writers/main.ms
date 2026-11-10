import (
    Bytes from "@std/bytes.ms",
    Sink, WriteStream, stdout from "@std/io/io.ms",
    json_writer from "@std/data/json.ms",
    csv_writer, CsvOptions from "@std/data/csv.ms",
    compile, render_to, to_data from "@std/text/template.ms",
)

type Point:
    x: Int
    label: String

// Prints the bytes it is given, so the output shows what the format writers produced.
type Echo:
    out: WriteStream[String]

impl Sink[Bytes] for Echo:
    var fn write(value: Bytes) Unit!:
        return self.out.write(value.decode_utf8().get(""))

    var fn flush() Unit!:
        return self.out.flush()

    var fn close() Unit!:
        return ok(unit)

fn echo() WriteStream[Bytes]:
    return WriteStream[Bytes](Echo(stdout()))

fn run() Unit!:
    var points = json_writer[Point](echo())
    try points.write(Point(1, "a \"quoted\" label"))
    try points.write(Point(2, "é😀"))

    var rows = csv_writer(echo(), CsvOptions(delimiter: ";"))
    try rows.write(["id", "name"])
    try rows.write(["1", "needs;quote"])
    try rows.write(["2", "multi\nline"])

    page := try compile(
        "\{\{ for p in points \}\}\{\{ p.x \}\}=\{\{ p.label \}\}\n\{\{ end \}\}"
    )
    data := try to_data({"points": [Point(1, "one"), Point(2, "two")]})
    var out = stdout()
    try render_to(page, data, var out)

export fn main() Int:
    result := run()
    if result.is_error(): return 1

    return 0
