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
    let dir = "{root}/{name}"
    let made = create_directory(dir)
    if made.is_error(): print("create_directory: {made.err()}")

    let path = "{dir}/a.txt"
    let written = write_file(path, name).wait()
    if written.is_error(): print("write_file: {written.err()}")

    let appended = append_file(path, "!").wait()
    if appended.is_error(): print("append_file: {appended.err()}")

    let renamed = rename(path, "{dir}/b.txt")
    if renamed.is_error(): print("rename: {renamed.err()}")

    let copied = copy("{dir}/b.txt", "{dir}/c.txt")
    if copied.is_error(): print("copy: {copied.err()}")

    let listed = list(dir)
    if let names = listed:
        return names.length()

    print("list: {listed.err()}")
    return -1

test "file-system calls from concurrent tasks":
    let root = try temporary_directory("ms-fs-tasks-")
    let first = root.clone()
    let second = root.clone()
    let a = promise(fn: ok(churn(first.clone(), "one")))
    let b = promise(fn: ok(churn(second.clone(), "two")))
    try a.wait() | try expect_equal(2)
    try b.wait() | try expect_equal(2)

    let text = try read_file("{root}/one/c.txt").wait()
    text | try expect_equal("one!".to_bytes())

    let _gone = remove(root, true)
