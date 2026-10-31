import read_file from "@std/fs.ms"
import stdout from "@std/io.ms"
import parse, stringify, JsonValue from "@std/json.ms"
import arguments from "@std/process.ms"
import clock from "@std/time.ms"

# Median-of-runs timing; mirrors node.js: warm-up, then at least `runs` runs and `budget` ns.
fn median_ns(body: fn() Int, budget: Int, runs: Int) Int:
    let _warm = body()
    var samples: List[Int] = []
    var total = 0

    while total < budget or samples.length() < runs:
        let started = clock().now()
        let _n = body()
        let elapsed = clock().now().difference(started).to_nanoseconds()
        samples.append(elapsed)
        total += elapsed

    let sorted = samples.sorted(fn(a: Int, b: Int) Int: a.compare(b))
    return sorted.get(sorted.length() / 2)

fn say(text: String) Unit:
    let _ignored = stdout().write(text)

# The typed case: a list of records, written without building a `JsonValue` first. The size is
# the text produced, the same 10,000 rows in `node.js` and `rust/`.
type Row:
    id: Int
    name: String
    tags: List[String]
    score: Float
    ok: Bool

fn row_list() List[Row]:
    var rows: List[Row] = []
    for i in 0..10000:
        rows.append(
            Row(
                id: i, name: "user{i}", tags: ["a", "b"], score: i.to_float() + 0.5,
                ok: i % 2 == 0
            )
        )
    return rows

fn records_body(rows: List[Row]) fn() Int:
    return fn() Int:
        if let out = stringify(rows): return out.byte_length()

        return 0

fn bench_records(budget: Int, runs: Int) Unit:
    let rows = row_list()
    let size = records_body(rows.clone())()
    let s = median_ns(records_body(rows), budget, runs)
    say("records\tstringify\t{s}\t{size}\n")

fn bench_one(name: String, op: String, budget: Int, runs: Int) Unit:
    if name == "records":
        bench_records(budget, runs)
        return

    let read = read_file("bench/perf/json/data/{name}.json")

    if let bytes = read:
        if let text = bytes.decode_utf8():
            bench_text(name, op, text, bytes.length(), budget, runs)
        else:
            say("{name}\tnot utf-8\n")
    else:
        say("{name}\tunreadable\n")

fn bench_text(
    name: String,
    op: String,
    text: String,
    size: Int,
    budget: Int,
    runs: Int
) Unit:
    if let tree = parse(text):
        if op == "doc":
            let d = median_ns(doc_body(text.clone()), budget, runs)
            say("{name}\tdoc\t{d}\t{size}\n")

        if op != "stringify" and op != "doc":
            let p = median_ns(parse_body(text.clone()), budget, runs)
            say("{name}\tparse\t{p}\t{size}\n")

        if op != "parse" and op != "doc":
            let s = median_ns(stringify_body(tree), budget, runs)
            say("{name}\tstringify\t{s}\t{size}\n")
    else:
        say("{name}\tinvalid json\n")

# Decodes to a record with no fields, so only the document build and its release are timed.
type Nothing:
    placeholder: Optional[Int] = none

fn doc_body(text: String) fn() Int:
    return fn() Int:
        if let _v = parse[Nothing](text): return 1

        return 0

fn parse_body(text: String) fn() Int:
    return fn() Int:
        if let _v = parse(text): return 1

        return 0

fn stringify_body(tree: JsonValue) fn() Int:
    return fn() Int:
        if let out = stringify(tree): return out.byte_length()

        return 0

# Arguments are `name` or `name:op` (op is parse or stringify); a leading `quick` makes it 5 runs, no time floor.
export fn main() Int:
    var budget = 1000000000
    var runs = 5

    for arg in arguments():
        if arg == "quick":
            budget = 0
        else:
            let parts = arg.split(":")
            var op = "both"
            if parts.length() > 1: op = parts.get(1).clone()
            bench_one(parts.get(0), op, budget, runs)

    return 0
