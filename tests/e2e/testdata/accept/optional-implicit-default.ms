import expect_equal, expect_false from "@std/test.ms"

type Config:
    name: String
    limit: Int?

fn find(name: String, limit: Int?, tag: String?) Int:
    if let l = limit:
        return l

    return name.length()

test "defaults":
    let c = Config(name: "a")
    try expect_false(not c.limit.is_none())
    try expect_equal(find("abc"), 3)
    try expect_equal(find("abc", 7), 7)
    try expect_equal(find("abc", tag: "x"), 3)
