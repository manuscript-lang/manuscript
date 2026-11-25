// ms: allow_effect std.fs.delete
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write
// ms: allow_effect std.process.run

// Plain test fixtures observed together: one `ms test a.ms b.ms ...` builds
// the runner and the shared standard-library modules once for a whole group. Only a
// fixture whose recording is a clean pass takes part, and only a batch observation that
// equals the recording counts; every other fixture is observed alone, so a fixture is
// never judged by a batch that disagrees with its recording.
import (
	JsonValue, stringify from "@std/data/json.ms",
	create_directory, temporary from "@std/os/fs.ms",

	Fixture, materialize, parent_length, read_text, string_member from "./corpus.ms",
	invoke,
	number,
	read_report,
	same,
	shape,
	text_value,
	without_member from "./observe.ms",
)

// The most fixtures one `ms test` builds.
size := 12
// Modules whose tests depend on the process, the clock or the network and so keep a
// process of their own.
solitary := ["@std/os/", "@std/net/", "@std/process", "@std/time", "@std/concurrency/"]

// Whether `fx` recorded a plain pass: one source file, no arguments or input, exit 0,
// quiet stderr and only the runner's own RUN and PASS lines on stdout.
fn batchable(fx Fixture) Bool {
	if (
		fx.phase != "test"
		or fx.is_dir
		or not fx.args.is_empty()
		or fx.stdin.length() > 0
		or fx.timeout > 0
	) {
		return false
	}
	if string_member(fx.expected, "stderr") != "" { return false }

	report := fx.expected.get("report")
	if report == null or fx.expected.get(
		"exit_code"
	) == null { return false }
	if stringify(fx.expected.get("exit_code") or JsonValue.Null).get() != "0" { return false }

	for line in string_member(report, "stdout").split("\n") {
		quiet := (
			line == ""
			or line.starts_with("RUN ")
			or line.starts_with("PASS ")
			or line.ends_with(" tests, 0 failed")
		)
		if not quiet { return false }
	}

	source := read_text(fx.path)
	for module in solitary {
		if source.contains(module) { return false }
	}
	return true
}

// `test` with its `index` replaced.
fn reindexed(one JsonValue, index Int) JsonValue {
	match one {
		ObjectValue(fields) => {
			var out = Map[String, JsonValue]()

			for field in fields.entries() {
				if field.key == "index" {
					out.add("index", number(index))
				} else {
					out.add(field.key.clone(), field.value.clone())
				}
			}

			return JsonValue.ObjectValue(out)
		}
		_ => return one.clone()
	}
}

// The report `ms test` would have printed for `entry` alone, cut from a batch
// report, or null when it has no tests.
fn slice(report JsonValue, entry String) JsonValue? {
	prefix := f"{entry}::"
	mine := (report.get("tests") or JsonValue.Null).as_list() or []
	picked := mine.filter(one => string_member(one, "name").starts_with(prefix))
	if picked.is_empty() { return null }

	duration := picked.map(
		one => ((one.get("duration_ns") or JsonValue.Null).as_int() or 0)
	).sum()
	var fields = Map[String, JsonValue]()
	for field in (report.as_map() or Map[String, JsonValue]()).entries() {
		fields.add(field.key.clone(), field.value.clone())
	}
	fields.add(
		"tests",
		JsonValue.ArrayValue(
			(0..picked.length()).map(at => reindexed(picked[at], at))
		),
	)

	var summary = Map[String, JsonValue]()
	summary.add("available", number(picked.length()))
	summary.add("selected", number(picked.length()))
	summary.add("passed", number(picked.length()))
	summary.add("failed", number(0))
	summary.add("skipped", number(0))
	summary.add("not_run", number(0))
	summary.add("duration_ns", number(duration))
	fields.add("summary", JsonValue.ObjectValue(summary))

	var kept = string_member(report, "stdout").split("\n").collect().filter(
		line => line.starts_with(f"RUN {prefix}") or line.starts_with(
			f"PASS {prefix}"
		)
	)
	kept.append(f"{picked.length()} tests, 0 failed")
	fields.add("stdout", text_value(kept.join("\n") + "\n"))
	return JsonValue.ObjectValue(fields)
}

// The observation of one fixture, as `test_phase` forms it from its report.
fn observation(report JsonValue) JsonValue {
	faultless := without_member(report, "fault")
	var keys = List[String]()
	shape(faultless, "", keys)
	keys.sort()

	var fields = Map[String, JsonValue]()
	fields.add("exit_code", number(0))
	fields.add("report", without_member(faultless, "duration_ns"))
	fields.add("shape", JsonValue.ArrayValue(keys.map(key => text_value(key))))
	fields.add("stderr", text_value(""))
	return JsonValue.ObjectValue(fields)
}

// The ids of the fixtures of `group` whose observation inside one batch equals their
// recording.
fn matched(ms String, group List[Fixture], build_type String) List[String] {
	scratch := temporary("ms-conform-").get()
	work := f"{scratch.path()}/w"
	void create_directory(work.clone()).get()

	var args = ["test"]

	for fx in group {
		materialize(fx, work.clone())
		args.append(fx.entry.clone())
	}

	args.extend(["--json", "--build-type", build_type.clone()])

	out := invoke(ms, group[0], args, work.clone(), "".to_bytes())
	report := read_report(out, work.clone())
	var ids = List[String]()
	if out.code != 0 or out.stderr != "" or report.get(
		"unparsable_json"
	) != null { return ids }

	for fx in group {
		cut := slice(report, fx.entry.clone())
		if cut == null { continue }

		if same(fx.expected, observation(cut)) {
			ids.append(fx.id.clone())
		}
	}

	return ids
}

// The ids of the fixtures of `chunk` that a batch of their directory neighbors proved.
export fn proven(ms String, chunk List[Fixture], build_type String) List[String] {
	var directories = Map[String, List[Fixture]]()

	for fx in chunk {
		if not batchable(fx.clone()) { continue }

		key := fx.path.slice(0, parent_length(fx.path))
		var group = (directories.get(key) or List[Fixture]()).clone()
		group.append(fx.clone())
		directories.add(key.clone(), group)
	}

	var ids = List[String]()

	for entry in directories.entries() {
		var at = 0

		while at < entry.value.length() {
			end := (at + size).min(entry.value.length())
			ids.extend(
				matched(
					ms.clone(),
					entry.value.slice(at, end).get().clone(),
					build_type.clone(),
				)
			)
			at = end
		}
	}

	return ids
}
