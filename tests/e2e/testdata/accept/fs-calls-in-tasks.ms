from "@std/bytes.ms" import Bytes
from "@std/fs.ms" import filesystem
from "@std/tasks.ms" import TaskGroup
from "@std/test.ms" import expect_equal, expect_ok

# With several tasks alive, file-system calls run on the blocking pool; the results must match
# the single-task behaviour.
def churn(root: String, name: String) -> Int:
    let fs = filesystem()
    let dir = f"{root}/{name}"
    let _made = fs.create_directory(dir)
    let path = f"{dir}/a.txt"
    let _written = fs.write_file(path, name)
    let _appended = fs.append_file(path, "!")
    let _renamed = fs.rename(path, f"{dir}/b.txt")
    let _copied = fs.copy_file(f"{dir}/b.txt", f"{dir}/c.txt")
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
    let a = group.spawn(lambda ch: churn(first, "one"))
    let b = group.spawn(lambda ch: churn(second, "two"))
    try a.result() | try expect_equal(2)
    try b.result() | try expect_equal(2)
    group.close()

    let text = try fs.read_file(f"{root}/one/c.txt")
    text | try expect_equal("one!".to_bytes())

    let _gone = fs.remove(root, True)
