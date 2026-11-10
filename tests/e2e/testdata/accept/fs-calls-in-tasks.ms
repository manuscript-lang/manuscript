import (
    append_file,
    copy,
    create_directory,
    list,
    read_file,
    remove,
    rename,
    temporary_directory,
    write_file
) from "@std/os/fs.ms"
import promise from "@std/concurrency/promise.ms"
import expect_equal from "@std/test/test.ms"

// With several tasks alive, file-system calls run on the blocking pool; the results must match
// the single-task behaviour.
fn churn(root: String, name: String) Int:
    dir := "{root}/{name}"
    made := create_directory(dir)
    if made.is_error(): print("create_directory: {made.err()}")

    path := "{dir}/a.txt"
    written := write_file(path, name).wait()
    if written.is_error(): print("write_file: {written.err()}")

    appended := append_file(path, "!").wait()
    if appended.is_error(): print("append_file: {appended.err()}")

    renamed := rename(path, "{dir}/b.txt")
    if renamed.is_error(): print("rename: {renamed.err()}")

    copied := copy("{dir}/b.txt", "{dir}/c.txt")
    if copied.is_error(): print("copy: {copied.err()}")

    listed := list(dir)
    if names := listed: return names.length()

    print("list: {listed.err()}")
    return -1

test "file-system calls from concurrent tasks":
    root := try temporary_directory("ms-fs-tasks-")
    first := root.clone()
    second := root.clone()
    a := promise(fn: ok(churn(first.clone(), "one")))
    b := promise(fn: ok(churn(second.clone(), "two")))
    try a.wait() | try expect_equal(2)
    try b.wait() | try expect_equal(2)

    text := try read_file("{root}/one/c.txt").wait()
    text | try expect_equal("one!".to_bytes())

    _gone := remove(root, true)
