import expect_equal, expect_ok from "@std/test/test.ms"
import promise, wait_all from "@std/concurrency/promise.ms"
import read_file, temporary, write_file from "@std/os/fs.ms"

fn size(path: String) Int!:
    let data = try read_file(path)
    return ok(data.length())

test "blocking file reads work from promises on any thread":
    let dir = temporary("manuscript-promise-") | try expect_ok
    let path = "{dir.path()}/data"
    try write_file(path, "0123456789")
    let all = wait_all([promise(fn: size(path)), promise(fn: size(path)), promise(fn: size(path))])
    for n in all.get([]):
        try expect_equal(n, 10)
