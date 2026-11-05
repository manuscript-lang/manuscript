import expect_equal from "@std/test/test.ms"

type Loader:
    load: fn(Int) Int

fn run(l: Loader) Int:
    let load = l.load
    return load(2)

test "a let of a function-valued field borrows it":
    let l = Loader(fn n: n + 1)
    try expect_equal(run(l), 3)
    try expect_equal(l.load(5), 6)
