import (
	expect_equal, expect_true from "@std/test/test.ms",
	JsonValue, parse from "@std/data/json.ms",
	temporary_directory, write_file from "@std/os/fs.ms",
	entries, branch, tree, last_id from "./session.ms",
)

fn entry(id: String, parent: String, text: String) String:
	return "\{\"type\":\"message\",\"id\":\"{id}\",\"parentId\":\"{parent}\",\"message\":\{\"role\":\"user\",\"content\":[\{\"type\":\"text\",\"text\":\"{text}\"\}]\}\}\n"

test "a fork leaves two branches and branch follows one":
	dir := try temporary_directory("pi-session-")
	path := "{dir}/s.jsonl"
	body := "{entry("a", "", "root")}{entry("b", "a", "left")}{entry("c", "a", "right")}"
	try write_file(path, body, replace: true).wait()

	all := try entries(path)
	try expect_equal(all.length(), 3)
	try expect_equal(branch(all, "b").length(), 2)
	try expect_equal(branch(all, "c").length(), 2)
	try expect_equal(last_id(all), "c")
	try expect_true(tree(all, "c").any(fn l: l.starts_with("* c")))

test "a compaction entry replaces everything before it":
	dir := try temporary_directory("pi-session-")
	path := "{dir}/s.jsonl"
	compaction := "\{\"type\":\"compaction\",\"id\":\"k\",\"parentId\":\"b\",\"summary\":\"did things\"\}\n"
	try write_file(
		path,
		"{entry("a", "", "one")}{entry("b", "a", "two")}{compaction}{entry("d", "k", "three")}",
		replace: true
	).wait()

	all := try entries(path)
	messages := branch(all, "d")
	try expect_equal(messages.length(), 2)
