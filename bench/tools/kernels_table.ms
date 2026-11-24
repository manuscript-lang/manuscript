// Validates complete trials before printing per-kernel minimum microseconds
// (bench/perf/kernels and competence). Rows are
// `<version> <kernel> <microseconds> <checksum>`; each successful producer ends its
// trial with `<version> # end`. Times below two microseconds are reported as folded
// rather than used in ratios.
import invalid, minimum from "./lib.ms"

export fn suite_names(suite String) List[String] {
	if suite == "kernels" {
		return [
			"sieve_5M", "nbody_200k", "life_128x128_50", "matmul_200", "trees_d16_x20",
			"collatz_1M", "map_count_2M", "mandel_400", "particles_1k_5k", "vm_5M",
			"expr_d20_x20", "closures_20M", "stencil_1000_20"
		]
	}
	return [
		"call_fib_36", "dispatch_100M", "closure_100M", "sort_1M", "text_1M",
		"strmap_10M", "errors_50M", "records_1M_x20", "grid2d_500x20", "struct_100M",
		"stack_20M", "optional_100M", "set_2M", "chars_1M"
	]
}

export fn base_versions() List[String] {
	return ["go", "ms", "rust", "rust-checked"]
}

export fn c_versions() List[String] {
	return ["c", "c-ms"]
}

// Kernels a version does not implement. Plain C has no map_count: a hand-rolled int64
// open-addressing table is not a like-for-like comparison with the general
// insertion-ordered `Map`.
export fn omitted(version String) List[String] {
	if version == "c" { return ["map_count_2M"] }
	return []
}

export fn ablations() List[String] {
	return ["c-ms-no-poll", "c-ms-no-overflow", "c-ms-no-bounds", "c-ms-unchecked"]
}

fn ratio(num Float, den Float) String {
	low := if num < den { num } else { den }
	if low < 2.0 { return "folded" }

	return (num / den).to_fixed(2) + "x"
}

fn same(a List[String], b List[String]) Bool {
	return a == b
}

export fn summarize(
	lines List[String],
	suite String,
	repeats Int,
	versions List[String],
) String! {
	if repeats < 1 { return invalid("repeats must be positive") }

	var allowed = [base_versions()]
	if suite == "kernels" {
		allowed = [
			base_versions().concat(c_versions()),
			base_versions().concat(c_versions()).concat(ablations()),
		]
	}
	if not allowed.any(a => same(a, versions)) {
		return invalid(f"unexpected versions for {suite}: {versions.join(" ")}")
	}

	names := suite_names(suite)
	var samples = Map[String, List[Float]]()
	var checks = Map[String, Set[Int]]()
	var trials = Map[String, Int]()
	for v in versions {
		trials.add(v.clone(), 0)
	}

	var pending = Set[String]()
	var active = ""

	for line in lines {
		parts := line.trim().split(" ").filter(p => p != "")
		if parts.length() < 2 or not versions.contains(parts[0]) {
			return invalid(f"invalid sample: {line.trim()}")
		}

		version := parts[0].clone()
		name := parts[1].clone()
		if active != "" and version != active {
			return invalid(f"unterminated {active} trial")
		}

		active = version.clone()

		if parts.length() == 3 and parts[1] == "#" and parts[2] == "end" {
			expected := names.filter(n => not omitted(active).contains(n))
			if (
				pending.length() != expected.length()
				or not expected.all(n => pending.contains(n))
			) {
				return invalid(f"incomplete {version} trial")
			}

			trials.add(version.clone(), trials.get_or(version, 0) + 1)
			pending = Set[String]()
			active = ""
			continue
		}

		if (
			parts.length() != 4
			or not names.contains(name)
			or omitted(version).contains(name)
			or pending.contains(name)
		) {
			return invalid(f"invalid kernel: {line.trim()}")
		}

		micros := parts[2].parse_int()
		check := parts[3].parse_int()
		if (micros == null) or (check == null) {
			return invalid(f"invalid sample: {line.trim()}")
		}
		if (micros) < 0 { return invalid(f"negative timing: {line.trim()}") }

		key := f"{name} {version}"
		var list = samples.get_or(key, List[Float]())
		list.append((micros).to_float())
		samples.add(key.clone(), list)

		var seen = checks.get_or(name, Set[Int]())
		seen.add(check)
		checks.add(name.clone(), seen)
		pending.add(name.clone())
	}

	if active != "" or versions.any(v => trials.get_or(v, 0) != repeats) {
		return invalid(f"expected {repeats} complete trials of every version")
	}

	for name in names {
		if checks.get_or(name, Set[Int]()).length() != 1 {
			return invalid(f"{name}: checksums differ between runs or versions")
		}
	}

	others := versions.filter(v => v != "go")
	extra := others.filter(v => v.starts_with("rust")).map(v => "ms / " + v)
	var head = others.map(v => f"{v} us | {v} / go").join(" | ")
	var rule = others.map(_v => "---:|---:|").join("")
	var rows = [
		f"Minimum of {repeats} rotating runs; microseconds. Complete trials and checksums verified.\n",
		"| kernel | go us | " + head + " | " + extra.join(" | ") + " |",
		"|---|---:|" + rule + extra.map(_e => "---:|").join(""),
	]

	for name in names {
		var times = Map[String, Float]()
		for v in versions {
			if not omitted(v).contains(name) {
				times.add(v.clone(), minimum(samples.get_or(f"{name} {v}", [])))
			}
		}

		go := times.get_or("go", 0.0)
		var cells = others.map(
			v => if omitted(v).contains(
				name
			) { "n/a | n/a" } else { f"{times.get_or(v, 0.0).to_fixed(0)} | {ratio(times.get_or(v, 0.0), go)}" }
		)
		ms := times.get_or("ms", 0.0)
		for v in others {
			if v.starts_with(
				"rust"
			) { cells.append(ratio(ms, times.get_or(v, 0.0))) }
		}
		rows.append(f"| {name} | {go.to_fixed(0)} | " + cells.join(" | ") + " |")
	}

	return ok(rows.join("\n"))
}
