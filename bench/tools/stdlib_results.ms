# Validates the shared `ms bench --json` result protocol before rendering comparisons (bench/perf/stdlib).
import Invalid, invalid from "./lib.ms"
import parse from "@std/data/json.ms"

export type Stats:
    operations: Int
    iterations: Int?
    samples: Int?
    median_ns: Float
    min_ns: Float?
    max_ns: Float?
    mean_ns: Float?
    stddev_ns: Float?

export type Bench:
    name: String
    status: String
    failure: String?
    stats: Stats?

type Diagnostic:
    message: String

type Document:
    benches: List[Bench]
    diagnostics: List[Diagnostic]?

fn finite(value: Float) Bool:
    return value >= 0.0 and value < 1.0e300

fn valid_optional(value: Float?) Bool:
    if let v = value: return finite(v)

    return true

# The passed cases of one `ms bench --json` document, in order.
export fn read_cases(output: String) Result[List[Bench], Invalid]:
    let parsed = parse[Document](output)
    if parsed.is_error(): return invalid("invalid benchmark document")

    let doc = parsed.get(Document(List[Bench](), none))
    let diagnostics = doc.diagnostics.get([])
    if diagnostics.length() > 0: return invalid(
        diagnostics.map(fn d: d.message.clone()).join("; ")
    )

    var seen = Set[String]()

    for bench in doc.benches:
        if seen.contains(bench.name): return invalid("duplicate case: {bench.name}")

        seen.add(bench.name.clone())
        if bench.status != "passed": return invalid(
            "{bench.name}: {bench.status}: {bench.failure.get("")}"
        )

        let stats = bench.stats.get(Stats(0, none, none, -1.0, none, none, none, none))
        if stats.operations <= 0: return invalid("invalid operations: {bench.name}")
        if (stats.iterations.get(1) <= 0) or (stats.samples.get(1) <= 0):
            return invalid("invalid iterations or samples: {bench.name}")
        if not finite(stats.median_ns): return invalid(
            "invalid median_ns: {bench.name}"
        )
        if not (
            valid_optional(stats.min_ns)
            and valid_optional(stats.max_ns)
            and valid_optional(stats.mean_ns)
            and valid_optional(stats.stddev_ns)
        ):
            return invalid("invalid timing: {bench.name}")

        if stats.min_ns.is_some() and stats.max_ns.is_some():
            if not (
                stats.min_ns.get(0.0) <= stats.median_ns
                and stats.median_ns <= stats.max_ns.get(0.0)
            ):
                return invalid("inconsistent timing range: {bench.name}")

    if doc.benches.length() == 0: return invalid("no cases were measured")

    return ok(doc.benches)

# Display labels: the part after `::`, or the whole name when two cases would collide.
export fn case_labels(names: List[String]) Map[String, String]:
    var counts = Map[String, Int]()
    var short = Map[String, String]()

    for name in names:
        let parts = name.split("::")
        let s = parts.slice(1, parts.length()).get([]).join("::")
        let label = if parts.length() > 1: s else: name.clone()
        short.add(name.clone(), label.clone())
        counts.add(label.clone(), counts.get(label).get(0) + 1)

    var labels = Map[String, String]()
    var distinct = Set[String]()

    for name in names:
        let s = short.get(name).get("")
        labels.add(name.clone(), if counts.get(s).get(0) == 1: s else: name.clone())
        distinct.add(labels.get(name).get(""))

    if distinct.length() != labels.length():
        var plain = Map[String, String]()
        for name in names:
            plain.add(name.clone(), name.clone())
        return plain

    return labels
