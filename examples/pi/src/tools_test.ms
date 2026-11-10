import (
	expect_equal, expect_true from "@std/test/test.ms",
	parse from "@std/data/json.ms",
	temporary_directory from "@std/os/fs.ms",
	execute, truncate_tail from "./tools.ms",
)

test "write, edit and read round trip":
	dir := try temporary_directory("pi-test-")
	path := "{dir}/a.txt"
	write := try parse("\{\"path\":\"{path}\",\"content\":\"one\\ntwo\\nthree\"\}")
	try expect_equal(execute("write", write).is_error, false)

	edit := try parse("\{\"path\":\"{path}\",\"oldText\":\"two\",\"newText\":\"2\"\}")
	try expect_equal(execute("edit", edit).is_error, false)

	read := try parse("\{\"path\":\"{path}\"\}")
	try expect_equal(execute("read", read).text, "one\n2\nthree")

test "edit refuses missing and ambiguous text":
	dir := try temporary_directory("pi-test-")
	path := "{dir}/b.txt"
	write := try parse("\{\"path\":\"{path}\",\"content\":\"x x\"\}")
	try expect_equal(execute("write", write).is_error, false)

	missing := try parse("\{\"path\":\"{path}\",\"oldText\":\"y\",\"newText\":\"z\"\}")
	try expect_true(execute("edit", missing).is_error)

	twice := try parse("\{\"path\":\"{path}\",\"oldText\":\"x\",\"newText\":\"z\"\}")
	try expect_true(execute("edit", twice).is_error)

test "bash reports output and failing exit codes":
	ok_call := try parse("\{\"command\":\"echo hi\"\}")
	try expect_equal(execute("bash", ok_call).text, "hi\n")

	bad_call := try parse("\{\"command\":\"echo no >&2; exit 3\"\}")
	result := execute("bash", bad_call)
	try expect_true(result.is_error)
	try expect_true(result.text.contains("exited with code 3"))

test "unknown tools are errors the model can read":
	args := try parse("\{\}")
	try expect_true(execute("nope", args).is_error)

test "tail truncation keeps the end":
	var lines = List[String]()
	for i in 0..3000: lines.append("line {i}")

	cut := truncate_tail(lines.join("\n"))
	try expect_true(cut.contains("line 2999"))
	try expect_true(not cut.contains("line 0\n"))
