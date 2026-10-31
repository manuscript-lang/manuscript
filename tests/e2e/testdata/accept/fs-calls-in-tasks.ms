import Bytes from "@std/bytes.ms"
import filesystem from "@std/fs.ms"
import TaskGroup from "@std/tasks.ms"
import expect_equal, expect_ok from "@std/test.ms"

# With several tasks alive, file-system calls run on the blocking pool; the results must match
# the single-task behaviour.
fn churn(root: String, name: String) Int:
    let fs = filesystem()
    let dir = "{root}/{name}"
    let _made = fs.create_directory(dir)
    let path = "{dir}/a.txt"
    let _written = fs.write_file(path, name)
    let _appended = fs.append_file(path, "!")
    let _renamed = fs.rename(path, "{dir}/b.txt")
    let _copied = fs.copy_file("{dir}/b.txt", "{dir}/c.txt")
    let listed = fs.list(dir)
    if let names = listed:
        return names.length()

    return -1

test "file-system calls from concurrent tasks":
    let fs = filesystem()
    let root = try fs.temporary_directory("ms-fs-tasks-")
    let first = root.clone()
    let second = root.clone()
    var group = TaskGroup[Int]()
    let a = group.spawn(fn ch: churn(first, "one"))
    let b = group.spawn(fn ch: churn(second, "two"))
    try a.result() | try expect_equal(2)
    try b.result() | try expect_equal(2)
    try group.close()

    let text = try fs.read_file("{root}/one/c.txt")
    text | try expect_equal("one!".to_bytes())

    let _gone = fs.remove(root, true)
