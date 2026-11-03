# Validates complete data-structure trials before comparing minimum ns/op (bench/perf/datastructures).
# Samples are `<version> <operation> <count> <nanoseconds>`. The runner appends `<version> # end` only after a successful
# producer. Producers do not emit checksums.
import invalid, left, right from "./lib.ms"

export type Operation:
    name: String
    count: Int

export fn operations() List[Operation]:
    return [
        Operation("list_append", 1000000), Operation("list_get_random", 1000000),
        Operation("list_sort_int", 1000000), Operation("list_sort_cmp", 300000),
        Operation("map_int_put_get", 2000000), Operation("map_str_put_get", 400000),
        Operation("set_int_add_contains", 2000000),
        Operation("string_build_split_join_replace", 200000),
        Operation("bytes_append", 4000000), Operation("pq_int_enqueue_dequeue", 600000),
        Operation("sorted_map_add_contains", 600000)
    ]

export fn versions() List[String]:
    return ["ms", "go", "rs"]

# Go has no sorted-map producer; all other rows are required in every version.
fn required(version: String) List[String]:
    let names = operations().map(fn o: o.name.clone())
    if version == "go": return names.filter(fn n: n != "sorted_map_add_contains")

    return names

fn count_of(name: String) Int:
    for op in operations():
        if op.name == name: return op.count
    return 0

fn ratio(num: Float?, den: Float?) String:
    if num.is_none() or den.is_none(): return "-"
    if num.get(0.0) == 0.0 or den.get(0.0) == 0.0: return "-"

    return (num.get(0.0) / den.get(0.0)).to_fixed(2)

fn cell(value: Float?) String:
    if let v = value: return right(v.to_fixed(1), 9)

    return right("-", 9)

export fn summarize(lines: List[String], repeats: Int) String!:
    if repeats < 1: return invalid("repeats must be positive")

    var best = Map[String, Float]()
    var trials = Map[String, Int]()
    for v in versions():
        trials.add(v.clone(), 0)

    var active = ""
    var pending = Set[String]()

    for line in lines:
        let parts = line.trim().split(" ").filter(fn p: p != "")
        if parts.length() < 2 or not versions().contains(parts[0]):
            return invalid("invalid sample: {line.trim()}")

        let version = parts[0].clone()
        let name = parts[1].clone()
        if active != "" and version != active: return invalid(
            "unterminated {active} trial"
        )

        active = version.clone()

        if parts.length() == 3 and parts[1] == "#" and parts[2] == "end":
            let need = required(version)
            if (
                pending.length() != need.length()
                or not need.all(fn n: pending.contains(n))
            ):
                return invalid("incomplete {version} trial")

            trials.add(version.clone(), trials.get(version).get(0) + 1)
            active = ""
            pending = Set[String]()
            continue

        if (
            parts.length() != 4
            or not required(version).contains(name)
            or pending.contains(name)
        ):
            return invalid("invalid operation: {line.trim()}")

        let ops = parts[2].parse_int()
        let ns = parts[3].parse_int()
        if (
            ops.is_none()
            or ns.is_none()
            or ops.get(0) != count_of(name)
            or ns.get(0) < 0
        ):
            return invalid("invalid count or timing: {line.trim()}")

        let key = "{name} {version}"
        let now = ns.get(0).to_float()

        if let prior = best.get(key):
            best.add(key.clone(), if now < prior: now else: prior)
        else:
            best.add(key.clone(), now)

        pending.add(name.clone())

    if active != "" or versions().any(fn v: trials.get(v).get(0) != repeats):
        return invalid("expected {repeats} complete trials of every version")

    var rows = [
        "Minimum of {repeats} rotating trials; ns/op. Complete trials and operation counts verified.",
        "Missing comparisons and zero timings have no ratio. Producers do not report checksums.\n",
        left("operation", 34) + right("ms", 9) + right("go", 9) + right(
            "rust", 9
        ) + right("ms/go", 8) + right("ms/rust", 9)
    ]

    for op in operations():
        let n = op.count.to_float()
        let m = best.get("{op.name} ms").get(0.0) / n
        var g: Float? = none
        if let t = best.get("{op.name} go"): g = t / n

        let r = best.get("{op.name} rs").get(0.0) / n
        rows.append(
            left(op.name, 34) + cell(m) + cell(g) + cell(r) + right(
                ratio(m, g), 8
            ) + right(ratio(m, r), 9)
        )

    return ok(rows.join("\n"))
