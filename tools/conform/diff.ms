// `conform diff`: the corpus observed under two ms binaries (or two build types) and compared directly.
import (
	Promise, promise from "@std/concurrency/promise.ms",
	system_info from "@std/os/system.ms",

	tool_ms from "../lib.ms",
	Args, number, one from "./args.ms",
	Fixture from "./corpus.ms",
	observe, same from "./observe.ms",
	Filter, select from "./select.ms",
)

// One line per fixture of `chunk`: `ok`, or `DIFF <id>`.
fn compare_chunk(ms_a, type_a, ms_b, type_b String, chunk List[Fixture]) List[String] {
	var lines = List[String]()

	for fx in chunk {
		if same(observe(ms_a, fx, type_a), observe(ms_b, fx, type_b)) {
			lines.append("ok")
		} else {
			lines.append(f"DIFF {fx.id}")
		}
	}

	return lines
}

// The ids of the fixtures of `chosen` that the two sides observe differently.
export fn differing(
	ms_a,
	type_a,
	ms_b,
	type_b String,
	chosen List[Fixture],
	jobs_wanted Int,
) List[String] {
	var jobs = jobs_wanted
	if jobs > 8 { jobs = 8 }
	if jobs < 1 { jobs = 1 }

	var chunks = List[List[Fixture]]()

	for worker in 0..jobs {
		var mine = List[Fixture]()
		for index in 0..chosen.length() {
			if index % jobs == worker {
				mine.append(chosen[index].clone())
			}
		}
		chunks.append(mine)
	}

	var tasks = List[Promise[List[String]]]()

	for worker in 0..jobs {
		first := ms_a.clone()
		second := ms_b.clone()
		first_type := type_a.clone()
		second_type := type_b.clone()
		mine := chunks[worker].clone()
		tasks.append(
			promise(
				() => ok(
					compare_chunk(
						first,
						first_type,
						second,
						second_type,
						mine,
					)
				)
			)
		)
	}

	var found = List[String]()
	for task in tasks {
		for line in task.wait().get_or(List[String]()) {
			if line != "ok" {
				found.append(line.slice(5, line.length()).clone())
			}
		}
	}
	found.sort()
	return found
}

export fn run_diff(root, corpus String, filter Filter, args Args) Int {
	ms_a := one(args, "ms-a", tool_ms(root))
	ms_b := one(args, "ms-b", ms_a)
	type_a := one(args, "build-type-a", "Release")
	type_b := one(args, "build-type-b", type_a)

	if ms_a == ms_b and type_a == type_b {
		print(
			"conform diff: both sides are the same ms and build type; pass --ms-b or --build-type-b"
		)
		return 64
	}

	chosen := select(corpus, filter)
	different := differing(
		ms_a,
		type_a,
		ms_b,
		type_b,
		chosen,
		number(args, "jobs", system_info().cpu_count),
	)
	for id in different { print(f"DIFF {id}") }
	print(
		f"{chosen.length()} fixtures: {chosen.length() - different.length()} same, {different.length()} differ"
	)
	if different.is_empty() { return 0 }

	return 1
}
