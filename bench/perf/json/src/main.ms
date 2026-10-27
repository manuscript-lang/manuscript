from "@std/fs.ms" import filesystem
from "@std/io.ms" import stdout
from "@std/json.ms" import parse, stringify, JsonValue
from "@std/process.ms" import arguments
from "@std/time.ms" import clock

# Median-of-runs timing; mirrors node.js: warm-up, then at least `runs` runs and `budget` ns.
def median_ns(body: Callable[[], Int], budget: Int, runs: Int) -> Int:
    let _warm = body()
    var samples: List[Int] = []
    var total = 0

    while total < budget or samples.length() < runs:
        let started = clock().now()
        let _n = body()
        let elapsed = clock().now().difference(started).to_nanoseconds()
        samples.append(elapsed)
        total += elapsed

    let sorted = samples.sorted(lambda (a: Int, b: Int) -> Int: a.compare(b))
    return sorted.get(sorted.length() / 2)

def say(text: String) -> Unit:
    let _ignored = stdout().write(text)

def bench_one(name: String, op: String, budget: Int, runs: Int) -> Unit:
    let read = filesystem().read_file(f"bench/perf/json/data/{name}.json")

    if let bytes = read:
        if let text = bytes.decode_utf8():
            bench_text(name, op, text, bytes.length(), budget, runs)
        else:
            say(f"{name}\tnot utf-8\n")
    else:
        say(f"{name}\tunreadable\n")

def bench_text(
    name: String,
    op: String,
    text: String,
    size: Int,
    budget: Int,
    runs: Int
) -> Unit:
    if let tree = parse(text):
        if op == "doc":
            let d = median_ns(doc_body(text.clone()), budget, runs)
            say(f"{name}\tdoc\t{d}\t{size}\n")

        if op != "stringify" and op != "doc":
            let p = median_ns(parse_body(text.clone()), budget, runs)
            say(f"{name}\tparse\t{p}\t{size}\n")

        if op != "parse" and op != "doc":
            let s = median_ns(stringify_body(tree), budget, runs)
            say(f"{name}\tstringify\t{s}\t{size}\n")
    else:
        say(f"{name}\tinvalid json\n")

# Decodes to a record with no fields, so only the document build and its release are timed.
type Nothing:
    placeholder: Optional[Int] = none

def doc_body(text: String) -> Callable[[], Int]:
    return lambda () -> Int:
        if let _v = parse[Nothing](text): return 1

        return 0

def parse_body(text: String) -> Callable[[], Int]:
    return lambda () -> Int:
        if let _v = parse(text): return 1

        return 0

def stringify_body(tree: JsonValue) -> Callable[[], Int]:
    return lambda () -> Int:
        if let out = stringify(tree): return out.byte_length()

        return 0

# Arguments are `name` or `name:op` (op is parse or stringify); a leading `quick` makes it 5 runs, no time floor.
export def main() -> Int:
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
