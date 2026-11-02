# Validates every string/list sample before reducing to per-case minima (bench/perf/strappend).
# Samples are whitespace-separated: `<trial> <version> <case> <elapsed> # <checksum>`.
import invalid, left, right from "./lib.ms"

export fn case_names() List[String]:
    var names = List[String]()
    for size in [4, 16, 64, 256, 1024, 8192]:
        names.append("append{size}")
    for count in [10000, 100000, 1000000]:
        names.append("list{count}")
    return names

export fn checksum(name: String) Int:
    if name.starts_with("append"):
        let size = name.slice(6, name.length()).get("0").parse_int().get(1)
        return 40 * size * (1000000 / size)

    return 40 * name.slice(4, name.length()).get("0").parse_int().get(0)

export fn summarize(lines: List[String], repeats: Int) String!:
    if repeats < 1: return invalid("repeats must be positive")

    let names = case_names()
    var seen = Map[String, Set[String]]()
    var best = Map[String, Int]()

    for line in lines:
        let f = line.replace("\t", " ").trim().split(" ").filter(fn p: p != "")
        if f.length() != 6 or f[4] != "#": return invalid(
            "invalid sample: {line.trim()}"
        )

        let trial = f[0].parse_int()
        let elapsed = f[3].parse_int()
        let check = f[5].parse_int()
        if trial.is_none() or elapsed.is_none() or check.is_none():
            return invalid("invalid sample: {line.trim()}")

        let version = f[1].clone()
        let name = f[2].clone()
        if (
            trial.get(-1) < 0
            or trial.get(-1) >= repeats
            or not (version == "ms" or version == "rust")
            or not names.contains(name)
        ):
            return invalid("unknown sample: {line.trim()}")

        let key = "{trial.get(0)} {version}"
        var cases = seen.get(key).get(Set[String]())
        if (
            cases.contains(name)
            or check.get(0) != checksum(name)
            or elapsed.get(0) <= 0
        ):
            return invalid("duplicate or invalid measurement: {line.trim()}")

        cases.add(name.clone())
        seen.add(key.clone(), cases)

        let id = "{name} {version}"

        if let prior = best.get(id):
            best.add(id.clone(), if elapsed.get(0) < prior: elapsed.get(0) else: prior)
        else:
            best.add(id.clone(), elapsed.get(0))

    if (
        seen.length() != repeats * 2
        or seen.values().any(fn c: (c.length() != names.length()))
    ):
        return invalid("missing benchmark samples")

    var rows = [
        left("size", 12) + " " + right("ms_us", 10) + " " + right(
            "rust_us", 10
        ) + " " + right("ratio", 8)
    ]

    for name in names.sorted():
        let ms = best.get("{name} ms").get(0)
        let rust = best.get("{name} rust").get(1)
        rows.append(
            left(name, 12) + " " + right("{ms}", 10) + " " + right(
                "{rust}", 10
            ) + " " + right((ms.to_float() / rust.to_float()).to_fixed(2) + "x", 8)
        )

    return ok(rows.join("\n"))
