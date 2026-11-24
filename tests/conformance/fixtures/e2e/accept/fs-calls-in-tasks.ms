// conform: tags=testing,tier-io
// conform: phase=test
import (
	promise from "@std/concurrency/promise.ms",
	append_file,
	copy,
	create_directory,
	list,
	read_file,
	remove,
	rename,
	temporary_directory,
	write_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",
)

// With several tasks alive, file-system calls run on the blocking pool; the results
// must match the single-task behaviour.
fn churn(root String, name String) Int:
	dir := f"{root}/{name}"
	made := create_directory(dir)
	if made.is_error(): print(f"create_directory: {made.err()}")

	path := f"{dir}/a.txt"
	written := write_file(path, name).wait()
	if written.is_error(): print(f"write_file: {written.err()}")

	appended := append_file(path, "!").wait()
	if appended.is_error(): print(f"append_file: {appended.err()}")

	renamed := rename(path, f"{dir}/b.txt")
	if renamed.is_error(): print(f"rename: {renamed.err()}")

	copied := copy(f"{dir}/b.txt", f"{dir}/c.txt")
	if copied.is_error(): print(f"copy: {copied.err()}")

	listed := list(dir)
	if names := listed: return names.length()

	print(f"list: {listed.err()}")
	return -1

test "file-system calls from concurrent tasks":
	root := temporary_directory("ms-fs-tasks-")?
	first := root.clone()
	second := root.clone()
	a := promise(() => ok(churn(first.clone(), "one")))
	b := promise(() => ok(churn(second.clone(), "two")))
	a.wait()? | expect_equal(2)?
	b.wait()? | expect_equal(2)?

	text := read_file(f"{root}/one/c.txt").wait()?
	text | expect_equal("one!".to_bytes())?

	_gone := remove(root, true)
