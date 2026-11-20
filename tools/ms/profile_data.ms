// The data side of `ms profile`: the runtime's folded stacks, the text report, the
// allocation report and the pprof encoding. Nothing here touches the file system.
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	expect_equal, expect_true from "@std/test/test.ms",

	quote from "./quote.ms",
)

export DEFAULT_HZ := 99
// Below this many samples the order of the busiest functions is mostly chance.
LOW_SAMPLES := 100

// One sampled stack, outermost frame first, with how many samples it received.
export type Stack:
	frames: List[String]
	count: Int

export type Folded:
	hz: Int = DEFAULT_HZ
	stacks: List[Stack] = []

export type TopEntry:
	function: String
	flat: Int
	cum: Int

fn Folded.total() Int:
	var sum = 0
	for stack in self.stacks: sum += stack.count
	return sum

fn Folded.period_nanos() Int:
	hz := if self.hz < 1: 1 else: self.hz
	return 1000000000 / hz

// The functions ordered by flat samples (descending), then cumulative, then name.
fn Folded.top() List[TopEntry]:
	var flat = Map[String, Int]()
	var cum = Map[String, Int]()

	for stack in self.stacks:
		if leaf := stack.frames.last():
			flat.update(leaf.clone(), 0, fn n: n + stack.count)

		var seen = Map[String, Bool]()

		for frame in stack.frames:
			if seen.contains(frame): continue

			seen.add(frame.clone(), true)
			cum.update(frame.clone(), 0, fn n: n + stack.count)

	var entries = List[TopEntry]()
	for entry in cum.entries():
		entries.append(
			TopEntry(
				function: entry.key.clone(),
				flat: flat.get_or(entry.key, 0),
				cum: entry.value,
			)
		)

	entries.sort(
		fn a,
		b:
			if a.flat != b.flat: return if a.flat > b.flat: -1 else: 1
			if a.cum != b.cum: return if a.cum > b.cum: -1 else: 1

			return a.function.compare(b.function)
	)

	return entries

// The `hz` of a `# hz=<n>` comment line, none when the comment says nothing about it.
fn hz_comment(line: String) String?:
	body := line.cut_prefix("#")
	if text := body:
		if value := text.trim().cut_prefix("hz="): return value.trim()
	return none

// Parses the runtime's folded-stack text.
export fn parse_folded(source: String) Folded!:
	var hz = DEFAULT_HZ
	var at = Map[String, Int]()
	var stacks = List[Stack]()
	var number = 0

	for raw in source.lines():
		number += 1

		line := raw.trim_end()
		if line.trim().is_empty(): continue

		if line.starts_with("#"):
			if value := hz_comment(line):
				parsed := value.parse_int()
				if parsed.is_none() or parsed.get_or(0) <= 0:
					return error(
						Error(
							f"line {number}: invalid hz header {quote(line)}"
						)
					)

				hz = parsed.get_or(0)

			continue

		bad := f"line {number}: expected '<frame>;<frame> <count>', got {quote(line)}"
		parts := line.rsplit_once(" ")
		if parts.is_none(): return error(Error(bad))

		split := parts.get()
		count := split.after.parse_int().get_or(0)
		if count <= 0: return error(Error(bad))

		frames := split.before.split(";")
		for frame in frames:
			if frame.is_empty(): return error(Error(bad))

		key := split.before.clone()

		if index := at.get(key):
			stacks[index].count += count
		else:
			at.add(key, stacks.length())
			stacks.append(Stack(frames: frames.clone(), count: count))

	return ok(Folded(hz: hz, stacks: stacks))

fn percent_of(part: Int, total: Int) Float:
	if total == 0: return 0.0
	return part.to_float() * 100.0 / total.to_float()

fn right(width: Int, value: String) String:
	return value.pad_start(width, " ")

fn left(width: Int, value: String) String:
	return value.pad_end(width, " ")

// The text report: a summary line and the `top` busiest functions.
export fn render_top(profile: Folded, top: Int) String:
	entries := profile.top()
	total := profile.total()
	seconds := (total * profile.period_nanos()).to_float() / 1e9
	shown := if entries.length() < top: entries.length() else: top
	var out = f"Showing top {shown} of {entries.length()} functions ({total} samples, {profile.hz} Hz, {seconds.to_fixed(2)}s)\n"
	out += f"{right(8, "flat")} {right(7, "flat%")} {right(8, "cum")} {right(7, "cum%")}  function\n"

	for at in 0..shown:
		entry := entries[at].clone()
		out += (
			f"{right(8, entry.flat.to_string())} {right(6, percent_of(entry.flat, total).to_fixed(2))}% "
			+ f"{right(8, entry.cum.to_string())} {right(6, percent_of(entry.cum, total).to_fixed(2))}%  {entry.function}\n"
		)

	if total < LOW_SAMPLES:
		out += f"note: {total} samples is too few to rank functions; run the program for several seconds (about {LOW_SAMPLES} samples or more) or give it more work\n"
	return out

// The percentage as the JSON document writes it: rounded to two places, an integer
// without a fraction.
export fn percent_text(part: Int, total: Int) String:
	if total == 0: return "0"

	scaled := (part.to_float() * 10000.0 / total.to_float() + 0.5).truncate_to_int().get_or(
		0
	)
	whole := scaled / 100
	fraction := scaled % 100
	if fraction == 0: return f"{whole}"

	digits := if fraction < 10: f"0{fraction}" else: f"{fraction}"
	return f"{whole}.{digits.trim_end_chars("0")}"

// The allocation profile: the runtime's two folded files, flattened to the function
// that allocates.
export type AllocRow:
	function: String
	allocations: Int
	bytes: Int

export type Allocs:
	period: Int
	allocations: Int
	bytes: Int
	top: Int
	rows: List[AllocRow]

// The value of a `# key <n>` comment in the runtime's folded text, 0 when absent.
fn comment_number(source: String, key: String) Int:
	for line in source.lines():
		body := line.cut_prefix("#")
		if text := body:
			if rest := text.trim().cut_prefix(key):
				if value := rest.trim().parse_int(): return value

	return 0

// An allocation belongs to the innermost Manuscript function: the runtime frames above
// it (`[runtime]`) are how it got the memory, not who asked.
fn owner(frames: List[String]) String:
	var at = frames.length()

	while at > 0:
		at -= 1
		if frames[at] != "[runtime]": return frames[at].clone()

	return "[runtime]"

// Reads the runtime's counts and bytes (`counts_text` and `bytes_text` of `path` and
// `path.bytes`) into the allocation profile.
export fn read_allocs(
	path: String,
	counts_text: String,
	bytes_text: String,
	top: Int,
) Allocs!:
	counts := parse_folded(counts_text).map_error(
		fn e: Error(f"cannot read {path}: {e.message}")
	)?
	bytes := parse_folded(bytes_text).map_error(
		fn e: Error(f"cannot read {path}.bytes: {e.message}")
	)?
	var rows = List[AllocRow]()
	var at = Map[String, Int]()

	for stack in counts.stacks:
		name := owner(stack.frames)
		slot := row_of(name, rows, at)
		rows[slot].allocations += stack.count

	for stack in bytes.stacks:
		name := owner(stack.frames)
		slot := row_of(name, rows, at)
		rows[slot].bytes += stack.count

	rows.sort(
		fn a,
		b:
			if a.allocations != b.allocations: return if a.allocations > b.allocations: -1 else: 1
			if a.bytes != b.bytes: return if a.bytes > b.bytes: -1 else: 1

			return a.function.compare(b.function)
	)

	return ok(
		Allocs(
			period: comment_number(counts_text, "period"),
			allocations: counts.total(),
			bytes: bytes.total(),
			top: top,
			rows: rows,
		)
	)

fn row_of(name: String, var rows: List[AllocRow], var at: Map[String, Int]) Int:
	if slot := at.get(name): return slot

	at.add(name.clone(), rows.length())
	rows.append(AllocRow(function: name.clone(), allocations: 0, bytes: 0))
	return rows.length() - 1

export fn render_allocs(profile: Allocs) String:
	shown := if profile.rows.length() < profile.top: profile.rows.length() else: profile.top
	var out = f"Allocations on the main thread: about {profile.allocations} ({profile.bytes} bytes), sampling every {profile.period}th; top {shown} of {profile.rows.length()} functions\n"
	out += f"{right(10, "allocs")} {right(7, "allocs%")} {right(12, "bytes")}  function\n"

	for at in 0..shown:
		row := profile.rows[at].clone()
		out += f"{right(10, row.allocations.to_string())} {right(6, percent_of(row.allocations, profile.allocations).to_fixed(2))}% {right(12, row.bytes.to_string())}  {row.function}\n"

	return out

// ---- pprof ----

fn varint(var out: BytesBuilder, first: Int) Void:
	var value = first

	while value >= 128:
		out.append((value % 128 + 128).to_uint8().get_or(0))
		value /= 128

	out.append(value.to_uint8().get_or(0))

fn varint_field(var out: BytesBuilder, field: Int, value: Int) Void:
	varint(out, field * 8)
	varint(out, value)

fn message(var out: BytesBuilder, field: Int, body: Bytes) Void:
	varint(out, field * 8 + 2)
	varint(out, body.length())
	out.append_bytes(body)

fn packed(var out: BytesBuilder, field: Int, values: List[Int]) Void:
	var body = BytesBuilder()
	for value in values: varint(body, value)
	message(out, field, body.build())

fn value_type(kind: Int, unit: Int) Bytes:
	var out = BytesBuilder()
	varint_field(out, 1, kind)
	varint_field(out, 2, unit)
	return out.build()

// Where `value` sits in the string table, appending it when new.
fn intern(value: String, var table: List[String], var at: Map[String, Int]) Int:
	if found := at.get(value): return found

	at.add(value.clone(), table.length())
	table.append(value.clone())
	return table.length() - 1

// A pprof `profile.proto` message, uncompressed (`go tool pprof` and `pprof` accept raw
// protobuf as well as gzip): two sample types (`samples/count` and `cpu/nanoseconds`),
// one function and one location per frame name, and a period of 1e9/hz.
export fn encode_pprof(profile: Folded, time_nanos: Int) Bytes:
	var strings = [""]
	var string_at = Map[String, Int]()
	string_at.add("", 0)

	samples_type := intern("samples", strings, string_at)
	count_unit := intern("count", strings, string_at)
	cpu_type := intern("cpu", strings, string_at)
	nanos_unit := intern("nanoseconds", strings, string_at)

	// One function and one location per frame name, numbered from 1 in first-seen
	// order.
	var ids = Map[String, Int]()
	var names = List[String]()

	for stack in profile.stacks:
		for frame in stack.frames:
			if not ids.contains(frame):
				names.append(frame.clone())
				ids.add(frame.clone(), names.length())

	period := profile.period_nanos()
	var out = BytesBuilder()
	message(out, 1, value_type(samples_type, count_unit))
	message(out, 1, value_type(cpu_type, nanos_unit))

	for stack in profile.stacks:
		var sample = BytesBuilder()
		var leaf_first = List[Int]()
		var at = stack.frames.length()

		while at > 0:
			at -= 1
			leaf_first.append(ids.get_or(stack.frames[at], 0))

		packed(sample, 1, leaf_first)
		packed(sample, 2, [stack.count, stack.count * period])
		message(out, 2, sample.build())

	for at in 0..names.length():
		id := at + 1
		var line = BytesBuilder()
		varint_field(line, 1, id)

		var location = BytesBuilder()
		varint_field(location, 1, id)
		message(location, 4, line.build())
		message(out, 4, location.build())

	for at in 0..names.length():
		id := at + 1
		name_index := intern(names[at], strings, string_at)
		var function = BytesBuilder()
		varint_field(function, 1, id)
		varint_field(function, 2, name_index)
		varint_field(function, 3, name_index)
		message(out, 5, function.build())

	for entry in strings: message(out, 6, entry.to_bytes())
	varint_field(out, 9, time_nanos)
	varint_field(out, 10, profile.total() * period)
	message(out, 11, value_type(cpu_type, nanos_unit))
	varint_field(out, 12, period)
	return out.build()

SAMPLE := "# hz=100\nmain;parse;read 40\nmain;parse 10\nmain;render 50\n\nmain;parse;read 10\n"

test "folded stacks sum repeats and rank by flat samples":
	profile := parse_folded(SAMPLE)?
	expect_equal(profile.hz, 100)?
	expect_equal(profile.total(), 110)?
	expect_equal(profile.stacks[0].frames, ["main", "parse", "read"])?
	expect_equal(profile.stacks[0].count, 50)?

	top := profile.top()
	expect_equal(top[0], TopEntry(function: "read", flat: 50, cum: 50))?
	expect_equal(top[1], TopEntry(function: "render", flat: 50, cum: 50))?
	expect_equal(top[2], TopEntry(function: "parse", flat: 10, cum: 60))?
	expect_equal(top[3], TopEntry(function: "main", flat: 0, cum: 110))?

test "recursion counts cumulative once":
	profile := parse_folded("f;f;f 4\n")?
	expect_equal(profile.top(), [TopEntry(function: "f", flat: 4, cum: 4)])?

test "a report of few samples says so":
	few := render_top(parse_folded("main;work 3\n# period 10\n")?, 5)
	expect_true(few.contains("note: 3 samples is too few to rank functions"))?
	expect_true(not render_top(parse_folded(SAMPLE)?, 5).contains("note:"))?

test "bad lines are rejected":
	for bad in ["main", "main x", "main 0", "main;;x 1", "# hz=0\nmain 1"]:
		expect_true(parse_folded(bad).is_error())?

test "the report text":
	text := render_top(parse_folded(SAMPLE)?, 2)
	expect_equal(
		text,
		"Showing top 2 of 4 functions (110 samples, 100 Hz, 1.10s)\n    flat   flat%      cum    cum%  function\n      50  45.45%       50  45.45%  read\n      50  45.45%       50  45.45%  render\n",
	)?

test "percentages print as short decimals":
	expect_equal(percent_text(50, 110), "45.45")?
	expect_equal(percent_text(1, 2), "50")?
	expect_equal(percent_text(1, 200), "0.5")?
	expect_equal(percent_text(1, 2000), "0.05")?
	expect_equal(percent_text(0, 0), "0")?

fn field_numbers(data: Bytes) List[Int]:
	var fields = List[Int]()
	var at = 0

	while at < data.length():
		tag := data.uvarint(at).get()
		at = tag.next_offset
		fields.append(tag.value.to_int().get_or(0) / 8)

		kind := tag.value.to_int().get_or(0) % 8

		if kind == 0:
			at = data.uvarint(at).get().next_offset
		else:
			size := data.uvarint(at).get()
			at = size.next_offset + size.value.to_int().get_or(0)

	return fields

fn count_of(fields: List[Int], field: Int) Int:
	var count = 0
	for entry in fields:
		if entry == field: count += 1
	return count

test "the pprof message has the expected fields":
	fields := field_numbers(encode_pprof(parse_folded("a;b 3\n")?, 42))
	expect_equal(count_of(fields, 1), 2)?
	expect_equal(count_of(fields, 2), 1)?
	expect_equal(count_of(fields, 4), 2)?
	expect_equal(count_of(fields, 5), 2)?
	expect_true(count_of(fields, 6) >= 7)?
	for field in [9, 10, 11, 12]:
		expect_equal(count_of(fields, field), 1)?
