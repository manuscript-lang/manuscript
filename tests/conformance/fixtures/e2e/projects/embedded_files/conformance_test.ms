import (
	walk from "@std/os/tree.ms",
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",

	files from "@assets",
)

test "embedded files read back byte for byte":
	tree := files()
	(
		tree.read("hello.txt", none) | expect_ok? | expect_equal(
			"hello \{braces\} and \"quotes\"\n".to_bytes()
		)?
	)
	(
		tree.read("nested/deep.txt", none) | expect_ok? | expect_equal(
			"deep\n".to_bytes()
		)?
	)

	data := tree.read("data.bin", none) | expect_ok?
	data.length() | expect_equal(256)?
	data.get(255, 0).to_int() | expect_equal(255)?

test "embedded tree walks in name order":
	found := walk(files()) | expect_ok?
	(
		found.map(fn e: e.path.clone())
		| expect_equal(["data.bin", "hello.txt", "nested", "nested/deep.txt"])?
	)

test "missing embedded files report NotFound":
	(
		files().read("nope.txt", none)
		| expect_error?
		| expect_equal(
			Error("filesystem: file or directory not found", kind: "ENOENT")
		)?
	)

test "embedded trees respect read limits and directories":
	tree := files()
	(
		tree.read("data.bin", 10) | expect_error? | expect_equal(
			Error("filesystem: limit exceeded", kind: "EOVERFLOW")
		)?
	)
	(
		tree.read("nested", none) | expect_error? | expect_equal(
			Error("filesystem: invalid input", kind: "EINVAL")
		)?
	)
	(
		tree.children("hello.txt", none) | expect_error? | expect_equal(
			Error("filesystem: invalid input", kind: "EINVAL")
		)?
	)
