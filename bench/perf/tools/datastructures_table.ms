// Validates complete data-structure trials before comparing minimum ns/op
// (bench/perf/datastructures). Samples are
// `<version> <operation> <count> <nanoseconds>`. The runner appends `<version> # end`
// only after a successful producer. Producers do not emit checksums.
import (
	invalid, left, right from "./lib.ms",
	read_trials from "./trials.ms",
)

export type Operation {
	name String
	count Int
}

export fn operations() List[Operation] {
	return [
		Operation("list_append", 1000000),
		Operation("list_get_random", 1000000),
		Operation("list_sort_int", 1000000),
		Operation("list_sort_cmp", 300000),
		Operation("map_int_put_get", 2000000),
		Operation("map_str_put_get", 400000),
		Operation("set_int_add_contains", 2000000),
		Operation("string_build_split_join_replace", 200000),
		Operation("bytes_append", 4000000),
		Operation("pq_int_enqueue_dequeue", 600000),
		Operation("sorted_map_add_contains", 600000),
	]
}

export fn versions() List[String] {
	return ["ms", "go", "rs"]
}

// Go has no sorted-map producer; all other rows are required in every version.
fn required(version String) List[String] {
	names := operations().map(o => o.name.clone())
	if version == "go" { return names.filter(n => n != "sorted_map_add_contains") }

	return names
}

fn count_of(name String) Int {
	for op in operations() {
		if op.name == name { return op.count }
	}
	return 0
}

fn ratio(num, den Float?) String {
	if (num == null) or (den == null) { return "-" }
	if (num) == 0.0 or (den) == 0.0 { return "-" }

	return ((num) / (den)).to_fixed(2)
}

fn cell(value Float?) String {
	v := value
	if v != null { return right(v.to_fixed(1), 9) }

	return right("-", 9)
}

export fn summarize(lines List[String], repeats Int) String! {
	rows := read_trials(lines, versions(), required, repeats)?
	var best = Map[String, Float]()

	for row in rows {
		if row.first != count_of(row.name) or row.second < 0 {
			return invalid(
				f"invalid count or timing: {row.version} {row.name} {row.first} {row.second}"
			)
		}

		key := f"{row.name} {row.version}"
		now := row.second.to_float()
		prior := best.get(key)
		best.add(key.clone(), now)
		if prior != null and prior < now { best.add(key.clone(), prior) }
	}

	var rows = [
		f"Minimum of {repeats} rotating trials; ns/op. Complete trials and operation counts verified.",
		"Missing comparisons and zero timings have no ratio. Producers do not report checksums.\n",
		left("operation", 34) + right("ms", 9) + right("go", 9) + right(
			"rust",
			9,
		) + right("ms/go", 8) + right("ms/rust", 9),
	]

	for op in operations() {
		n := op.count.to_float()
		m := best.get_or(f"{op.name} ms", 0.0) / n
		var g Float? = null
		t := best.get(f"{op.name} go")
		if t != null { g = t / n }

		r := best.get_or(f"{op.name} rs", 0.0) / n
		rows.append(
			left(op.name, 34) + cell(m) + cell(g) + cell(r) + right(
				ratio(m, g),
				8,
			) + right(ratio(m, r), 9)
		)
	}

	return ok(rows.join("\n"))
}
