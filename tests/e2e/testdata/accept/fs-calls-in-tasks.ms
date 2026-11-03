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
    let _made = create_directory(dir)
    let path = "{dir}/a.txt"
    let _written = write_file(path, name).wait()
    let _appended = append_file(path, "!")
    let _renamed = rename(path, "{dir}/b.txt")
    let _copied = copy("{dir}/b.txt", "{dir}/c.txt")
    let listed = list(dir)
    if let names = listed:
        return names.length()

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
