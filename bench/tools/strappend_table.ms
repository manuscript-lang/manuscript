// Validates every string/list sample before reducing to per-case minima
// (bench/perf/strappend). Samples are whitespace-separated:
// `<trial> <version> <case> <elapsed> # <checksum>`.
import invalid, left, right from "./lib.ms"

export fn case_names() List[String]:
	var names = List[String]()
	for size in [4, 16, 64, 256, 1024, 8192]:
		names.append(f"append{size}")
	for count in [10000, 100000, 1000000]:
		names.append(f"list{count}")
	return names

export fn checksum(name: String) Int:
	if name.starts_with("append"):
		size := name.slice(6, name.length()).parse_int() or 1
		return 40 * size * (1000000 / size)

	return 40 * (name.slice(4, name.length()).parse_int() or 0)

export fn summarize(lines: List[String], repeats: Int) String!:
	if repeats < 1: return invalid("repeats must be positive")

	names := case_names()
	var seen = Map[String, Set[String]]()
	var best = Map[String, Int]()

	for line in lines:
		f := line.replace("\t", " ").trim().split(" ").filter(fn p: p != "")
		if f.length() != 6 or f[4] != "#": return invalid(
			f"invalid sample: {line.trim()}"
		)

		trial := f[0].parse_int()
		elapsed := f[3].parse_int()
		check := f[5].parse_int()
		if (trial == null) or (elapsed == null) or (check == null):
			return invalid(f"invalid sample: {line.trim()}")

		version := f[1].clone()
		name := f[2].clone()
		if (
			(trial or (-1)) < 0
			or (trial or (-1)) >= repeats
			or not (version == "ms" or version == "rust")
			or not names.contains(name)
		):
			return invalid(f"unknown sample: {line.trim()}")

		key := f"{(trial or 0)} {version}"
		var cases = seen.get_or(key, Set[String]())
		if (
			cases.contains(name)
			or (check or 0) != checksum(name)
			or (elapsed or 0) <= 0
		):
			return invalid(f"duplicate or invalid measurement: {line.trim()}")

		cases.add(name.clone())
		seen.add(key.clone(), cases)

		id := f"{name} {version}"

		if prior := best.get(id):
			best.add(id.clone(), if (elapsed or 0) < prior: (elapsed or 0) else: prior)
		else:
			best.add(id.clone(), elapsed or 0)

	if (
		seen.length() != repeats * 2
		or seen.values().any(fn c: (c.length() != names.length()))
	):
		return invalid("missing benchmark samples")

	var rows = [
		left("size", 12) + " " + right("ms_us", 10) + " " + right(
			"rust_us",
			10,
		) + " " + right("ratio", 8)
	]

	for name in names.sorted():
		ms := best.get_or(f"{name} ms", 0)
		rust := best.get_or(f"{name} rust", 1)
		rows.append(
			left(name, 12) + " " + right(f"{ms}", 10) + " " + right(
				f"{rust}",
				10,
			) + " " + right((ms.to_float() / rust.to_float()).to_fixed(2) + "x", 8)
		)

	return ok(rows.join("\n"))
