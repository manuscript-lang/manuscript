// Choosing fixtures, the known-failure allowlist, and the recorded expectation of a
// fixture.
import (
	JsonValue, parse from "@std/data/json.ms",
	read_file from "@std/os/fs.ms",

	Fixture, Phase from "./fixture.ms",
)

// Which fixtures to run.
export type Filter:
	// A fixture matches when it has any of these tags (empty means all).
	tags: List[String] = []
	exclude_tags: List[String] = []
	phases: List[Phase] = []
	// Substring match on the fixture id (any of).
	ids: List[String] = []
	// Keep the fixtures whose position among the matches modulo `shard_count` is
	// `shard_index`.
	shard_index: Int = 0
	shard_count: Int = 1

fn matches(fixture: Fixture, filter: Filter) Bool:
	if not filter.tags.is_empty():
		if not fixture.tags.any(fn t: filter.tags.contains(t)): return false
	if fixture.tags.any(fn t: filter.exclude_tags.contains(t)): return false

	if not filter.phases.is_empty():
		if not filter.phases.contains(fixture.phase): return false
	if not filter.ids.is_empty():
		if not filter.ids.any(fn i: fixture.id.contains(i)): return false
	return true

// The positions in `all` of the fixtures `filter` keeps.
export fn select(all: List[Fixture], filter: Filter) List[Int]:
	var kept = List[Int]()
	var seen = 0

	for at in 0..all.length():
		if not matches(all[at], filter): continue

		if seen % filter.shard_count == filter.shard_index: kept.append(at)
		seen += 1

	return kept

// Known failures: ids, `prefix*` patterns, `#` comments.
export type ExpectFail:
	exact: List[String] = []
	prefixes: List[String] = []

export fn parse_expect_fail(text: String) ExpectFail:
	var allow = ExpectFail()

	for raw in text.lines():
		line := raw.split("#").first().get_or("").trim()
		if line.is_empty(): continue

		if prefix := line.cut_suffix("*"):
			allow.prefixes.append(prefix.clone())
		else:
			allow.exact.append(line.clone())

	return allow

export fn load_expect_fail(path: String) Result[ExpectFail, String]:
	data := read_file(path).wait().map_error(fn e: f"{path}: {e.message}")?
	text := data.decode_utf8().ok_or(f"{path}: not UTF-8")?
	return ok(parse_expect_fail(text))

fn ExpectFail.contains(id: String) Bool:
	if self.exact.contains(id): return true
	return self.prefixes.any(fn p: id.starts_with(p))

// The `expected` member of the fixture's recorded document.
export fn load_expected(fixture: Fixture) Result[JsonValue, String]:
	path := fixture.expected_path
	data := read_file(path).wait().map_error(fn e: f"{path}: {os_text(e)}")?
	text := data.decode_utf8().ok_or(f"{path}: not UTF-8")?
	doc := parse(text).map_error(fn e: e.message)?
	expected := doc.get("expected").ok_or(f"{path}: no \"expected\" key")?
	return ok(expected.clone())

// The operating system's own wording for the failures a missing expectation file
// raises.
fn os_text(failure: Error) String:
	if failure.kind == "ENOENT": return "No such file or directory (os error 2)"
	return failure.message.clone()
