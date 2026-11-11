// Validates equivalent work before comparing paired process samples
// (bench/perf/programs).
import fixed, invalid, median from "./lib.ms"

export type Op:
	name: String
	count: Int

export fn ops() List[Op]:
	return [
		Op("string_append_50k", 50000),
		Op("read_line", 200000),
		Op("map_put_get_8k", 16000),
		Op("int_eq", 10000000),
		Op("generic_call", 100000000),
		Op("method_call", 100000000),
		Op("try", 100000000),
		Op("match", 100000000),
		Op("builtin_length", 100000000),
		Op("for_list", 100000000),
	]

export SINK := [
	50000, 63992000, 3333334, 4999999950000000, 100000000, 5000000050000000, 633333333,
	10000000000, 49999950000000
]
VERSIONS := ["ms", "go", "rust", "rust-checked"]

fn title(version: String) String:
	if version == "ms": return "Manuscript"
	if version == "go": return "Go"
	if version == "rust": return "Rust"

	return "Rust, overflow checks"

fn ops_of(name: String) Int?:
	for op in ops():
		if op.name == name: return op.count
	return none

// One sample line: `<version> <operation> <count> <ns>` or
// `<version> # sink <checksums>`.
export fn summarize(lines: List[String], repeats: Int) String!:
	if repeats < 1: return invalid("repeats must be positive")

	var samples = Map[String, List[Float]]()
	var pending = Map[String, Set[String]]()
	var sinks = Map[String, Int]()

	for line in lines:
		parts := line.trim().split(" ").filter(fn p: p != "")
		if parts.length() < 2 or not VERSIONS.contains(parts[0]):
			return invalid("invalid sample: {line.trim()}")

		version := parts[0].clone()
		name := parts[1].clone()
		if not pending.contains(version): pending.add(version.clone(), Set[String]())

		if name == "#":
			var sink = List[Int]()
			for p in parts.slice(3, parts.length()).get([]):
				sink.append(p.parse_int().get(-1))
			if parts.length() < 3 or parts[2] != "sink" or sink != SINK:
				return invalid("incorrect {version} checksum")
			if pending.get_or(version, Set[String]()).length() != ops().length():
				return invalid("incomplete {version} sample")

			pending.add(version.clone(), Set[String]())
			sinks.add(version.clone(), sinks.get_or(version, 0) + 1)
			continue

		want := ops_of(name)
		if (
			parts.length() != 4
			or want.is_none()
			or pending.get_or(version, Set[String]()).contains(name)
		):
			return invalid("invalid operation: {line.trim()}")

		count := parts[2].parse_int().get(-1)
		elapsed := parts[3].parse_int().get(-1)
		if count != want.get(0) or elapsed <= 0:
			return invalid("incorrect work count or timing: {line.trim()}")

		key := "{version} {name}"
		var list = samples.get_or(key, List[Float]())
		list.append(elapsed.to_float() / count.to_float())
		samples.add(key.clone(), list)

		var seen_ops = pending.get_or(version, Set[String]())
		seen_ops.add(name.clone())
		pending.add(version.clone(), seen_ops)

	var seen = List[String]()
	for v in VERSIONS:
		if sinks.get_or(v, 0) > 0 or not pending.get_or(v, Set[String]()).is_empty(): seen.append(
			v.clone()
		)
	if not seen.contains("ms") or not seen.contains("go"):
		return invalid("expected ms and go samples")

	for v in seen:
		if (
			not pending.get_or(v, Set[String]()).is_empty()
			or sinks.get_or(v, 0) != repeats
		):
			return invalid("expected {repeats} complete {v} samples")

	others := seen.filter(fn v: v != "ms" and v != "go")
	order := ["ms", "go"].concat(others)
	var heads = order.map(fn v: title(v))
	heads.append("ms / Go")
	for v in others:
		heads.append("ms / {title(v)}")

	var rows = List[String]()

	for op in ops():
		var med = Map[String, Float]()
		for v in seen:
			med.add(v.clone(), median(samples.get_or("{v} {op.name}", [])))

		var cells = order.map(fn v: fixed(med.get_or(v, 0.0), 2))
		ms := med.get_or("ms", 0.0)
		cells.append(fixed(ms / med.get_or("go", 1.0), 2) + "x")
		for v in others:
			cells.append(fixed(ms / med.get_or(v, 1.0), 2) + "x")
		rows.append("| {op.name} | {op.count} | " + cells.join(" | ") + " |")

	rule := heads.map(fn _h: "---:|").join("")
	return ok("""
        Median of {repeats} alternating runs; ns/op. Checksums and operation counts verified.

        | operation | ops | {heads.join(" | ")} |
        |---|---:|{rule}
        {rows.join("\n")}
        """)
