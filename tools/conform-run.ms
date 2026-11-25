// The conformance corpus replayed against an ms binary, in Manuscript: it reads each
// fixture's recorded expectation (<name>.expected.json beside a .ms file, or
// expected.json in a project directory with a conform.meta), observes the ms under test
// (tools/conform/observe.ms) and counts the fixtures whose observation equals the
// recorded one. The other corpus commands (list, stats, lint, retag, diff, fuzz-gen,
// fuzz, harvest) are tools/conform.ms.
//
// `--record` writes each selected fixture's expectation from the ms under test instead of
// comparing (`--only-missing` keeps recorded ones, `--no-stable-check` skips the second
// observation, `--prune` deletes fixtures that cannot be recorded). MS names the ms
// under test (default .artifacts/build/ci/src/cli/ms). CONFORM_DIFF=1 prints each
// failure's expected and observed (first 2500 characters). CONFORM_BUILD_TYPE picks the
// build type of run and test (default Release). Fixtures tagged `aliasing` are left out
// of check, run and test as the gate does (`--exclude-tag aliasing`). Usage: ms run
// tools/conform-run.ms
// -- [--phase parse|check|run|test] [--jobs N] [fixture id substring ...] Prints
// `<phase>: passed/total` and one `FAIL <id>` line per difference.
import (
	Bytes from "@std/bytes.ms",
	Promise, promise from "@std/concurrency/promise.ms",
	JsonValue, StringifyOptions, parse, stringify from "@std/data/json.ms",
	arguments, environment, working_directory from "@std/os/env.ms",
	CopyOptions,
	GlobOptions,
	access,
	copy,
	create_directory,
	glob,
	read_file,
	remove,
	temporary,
	write_file from "@std/os/fs.ms",
	CommandOutput, RunOptions, run from "@std/os/process.ms",
	system_info from "@std/os/system.ms",
	seconds from "@std/time.ms",

	Fixture, fixtures, read_text, text_of from "./conform/corpus.ms",
	number, observe, same, text_value from "./conform/observe.ms",
	tool_ms from "./lib.ms",
)

// Observes each fixture of `chunk`: one `ok` or `FAIL <id>` line apiece.
fn sweep(ms, build_type String, chunk List[Fixture], detail Bool) List[String] {
	var lines = List[String]()

	for fx in chunk {
		observed := observe(ms, fx, build_type)

		if same(fx.expected, observed) {
			lines.append("ok")
		} else if detail {
			lines.append(
				f"FAIL {fx.id}\n  expected: {clipped(fx.expected)}\n  observed: {clipped(observed)}"
			)
		} else {
			lines.append(f"FAIL {fx.id}")
		}
	}

	return lines
}

// The first 2500 characters of a value, for `CONFORM_DIFF=1` failure reports.
fn clipped(value JsonValue) String {
	text := stringify(value).get()
	if text.length() <= 2500 { return text.clone() }

	return f"{text.slice(0, 2500)}..."
}

// The text of `ms version`, stored in each expectation for provenance.
fn oracle_version(ms String) String {
	result := run(ms, ["version"], RunOptions(timeout: seconds(30))).wait()
	if out := result { return text_of(out.stdout).trim().clone() }

	return ""
}

// Why `observed` cannot be recorded, or "".
fn unrecordable(observed JsonValue) String {
	for key in ["harness_error", "spawn_error", "timed_out", "unparsable_json"] {
		if observed.get(
			key
		) != null { return f"observation has {key}" }
	}

	report := observed.get("report")
	if report != null {
		if report.get(
			"unparsable_json"
		) != null { return "ms test did not print JSON" }
	}
	return ""
}

// Records each fixture of `chunk`: one `wrote`, `same`, `kept` or `REJECT <id>: <why>`
// line apiece.
fn record_chunk(
	ms,
	build_type String,
	chunk List[Fixture],
	version String,
	stable,
	only_missing,
	prune Bool,
) List[String] {
	var lines = List[String]()

	for fx in chunk {
		if only_missing and access(fx.sidecar, 0).is_ok() {
			lines.append("kept")
			continue
		}

		first := observe(ms, fx, build_type)
		why := unrecordable(first)
		var rejected = why
		if rejected == "" and stable and not fx.deterministic {
			if not same(first, observe(ms, fx, build_type)) { rejected = "unstable between runs" }
		}

		if rejected != "" {
			if prune { void remove(fx.path, recursive: true) }
			if prune and not fx.is_dir { void remove(fx.sidecar) }
			lines.append(f"REJECT {fx.id}: {rejected}")
			continue
		}

		var document = Map[String, JsonValue]()
		document.add("format", number(1))
		document.add("phase", text_value(fx.phase))
		document.add("oracle", text_value(version))
		document.add("expected", first)

		text := (
			stringify(
				JsonValue.ObjectValue(document),
				StringifyOptions(indent: 2),
			).get()
			+ "\n"
		)

		if read_text(fx.sidecar) == text {
			lines.append("same")
			continue
		}

		write_file(fx.sidecar, text, replace: true).wait().get()
		lines.append("wrote")
	}

	return lines
}

fn main() Int {
	root := working_directory().get()
	var phase = "parse"

	// One fixture per processor, at most 8: every fixture builds with clang-sized
	// tools, so more jobs than processors stretch each one's wall time past its timeout
	// on a loaded 4-core runner.
	var jobs = system_info().cpu_count
	if jobs > 8 { jobs = 8 }

	var recording = false
	var only_missing = false
	var stable = true
	var prune = false
	var filters = List[String]()
	var words = List[String]()
	for word in arguments() { words.append(word.clone()) }

	var at = 0

	while at < words.length() {
		if words[at] == "--phase" {
			at += 1
			phase = words[at].clone()
		} else if words[at] == "--jobs" {
			at += 1
			jobs = words[at].parse_int() or jobs
		} else if words[at] == "--record" {
			recording = true
		} else if words[at] == "--only-missing" {
			only_missing = true
		} else if words[at] == "--no-stable-check" {
			stable = false
		} else if words[at] == "--prune" {
			prune = true
		} else {
			filters.append(words[at].clone())
		}

		at += 1
	}

	if phase != "parse" and phase != "check" and phase != "run" and phase != "test" {
		print(f"conform-run: unknown phase {phase}")
		return 64
	}

	ms := tool_ms(root.clone())
	var build_type = "Release"
	configured := environment().get_or(Map[String, String]()).get("CONFORM_BUILD_TYPE")
	if configured != null { build_type = configured.clone() }

	show_diff := environment().get_or(Map[String, String]()).get("CONFORM_DIFF") != null
	var chosen = List[Fixture]()

	for fx in fixtures(f"{root}/tests/conformance/fixtures", phase, filters) {
		if phase != "parse" and fx.tags.contains("aliasing") { continue }

		chosen.append(fx.clone())
	}

	var jobs_count = jobs
	if jobs_count < 1 { jobs_count = 1 }

	// A promise reads its captures until it is dropped, so the chunks outlive the loop
	// that starts them.
	var chunks = List[List[Fixture]]()

	for worker in 0..jobs_count {
		var mine = List[Fixture]()
		for index in 0..chosen.length() {
			if index % jobs_count == worker {
				mine.append(chosen[index].clone())
			}
		}
		chunks.append(mine)
	}

	if recording {
		version := oracle_version(ms.clone())

		// A promise keeps what it captures, so each one gets its own copies.
		stable_now := stable
		only_missing_now := only_missing
		prune_now := prune
		var recorders = List[Promise[List[String]]]()

		for worker in 0..jobs_count {
			tool := ms.clone()
			kind := build_type.clone()
			mine := chunks[worker].clone()
			release := version.clone()
			recorders.append(
				promise(
					() => ok(
						record_chunk(
							tool,
							kind,
							mine,
							release,
							stable_now,
							only_missing_now,
							prune_now,
						)
					)
				)
			)
		}

		var counts = Map[String, Int]()

		for task in recorders {
			for line in task.wait().get_or(List[String]()) {
				if line.starts_with("REJECT") {
					print(line)
					counts.add("rejected", (counts.get("rejected") or 0) + 1)
				} else {
					counts.add(line.clone(), (counts.get(line) or 0) + 1)
				}
			}
		}

		print(
			f"{phase}: wrote {(counts.get("wrote") or 0)}, same {(counts.get("same") or 0)}, kept {(counts.get("kept") or 0)}, rejected {(counts.get("rejected") or 0)}"
		)
		if (counts.get("rejected") or 0) > 0 { return 1 }

		return 0
	}

	var tasks = List[Promise[List[String]]]()

	for worker in 0..jobs_count {
		tool := ms.clone()
		kind := build_type.clone()
		mine := chunks[worker].clone()
		detail := show_diff
		tasks.append(promise(() => ok(sweep(tool, kind, mine, detail))))
	}

	var passed = 0

	for task in tasks {
		for line in task.wait().get_or(List[String]()) {
			if line == "ok" {
				passed += 1
			} else {
				print(line)
			}
		}
	}

	print(f"{phase}: {passed}/{chosen.length()}")
	if passed != chosen.length() { return 1 }

	return 0
}
