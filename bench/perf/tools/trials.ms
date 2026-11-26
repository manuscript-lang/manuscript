// The trial protocol shared by the benchmark producers that report one row per case
// (bench/perf/kernels, competence and datastructures). A producer prints
// `<version> <case> <number> <number>` for each case it ran and ends a successful
// trial with `<version> # end`. `read_trials` checks the structure (known version, no
// interleaved trials, every required case exactly once per trial, `repeats` complete
// trials of every version) and hands back the rows; each table then checks what its
// two numbers mean and reduces them.
import invalid, rotate, sample from "./lib.ms"

export type Row {
	version, name String
	first, second Int
}

// The rows of `lines` in order, or why they are not `repeats` complete trials of every
// one of `versions`. `required(version)` names the cases a trial of that version holds.
export fn read_trials(
	lines,
	versions List[String],
	required fn(String) List[String],
	repeats Int
) List[Row]! {
	if repeats < 1 { return invalid("repeats must be positive") }

	var rows = List[Row]()
	var trials = Map[String, Int]()
	for v in versions {
		trials.add(v.clone(), 0)
	}

	var active = ""
	var pending = Set[String]()

	for line in lines {
		parts := line.trim().split(" ").collect().filter(p => p != "")
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
			need := required(version)
			if (
				pending.length() != need.length()
				or not need.all(n => pending.contains(n))
			) {
				return invalid(f"incomplete {version} trial")
			}

			trials.add(version.clone(), trials.get_or(version, 0) + 1)
			active = ""
			pending = Set[String]()
			continue
		}

		if (
			parts.length() != 4
			or not required(version).contains(name)
			or pending.contains(name)
		) {
			return invalid(f"invalid case: {line.trim()}")
		}

		first := parts[2].parse_int()
		second := parts[3].parse_int()
		if (first == null) or (second == null) {
			return invalid(f"invalid count or timing: {line.trim()}")
		}

		rows.append(Row(version.clone(), name.clone(), first, second))
		pending.add(name)
	}

	if active != "" or versions.any(v => trials.get_or(v, 0) != repeats) {
		return invalid(f"expected {repeats} complete trials of every version")
	}

	return ok(rows)
}

// Runs `n` rounds of every version's executable, in a different order each round so no
// version always goes first, and returns each output line prefixed with its version and
// followed by that version's `# end` line.
export fn run_trials(
	versions List[String],
	exe fn(String) String,
	n Int
) List[String]! {
	var raw = List[String]()

	for i in 0..n {
		for v in rotate(versions, i) {
			for line in sample(exe(v), [])?.split("\n") {
				if line != "" { raw.append(f"{v} {line}") }
			}
			raw.append(f"{v} # end")
		}
	}

	return ok(raw)
}
