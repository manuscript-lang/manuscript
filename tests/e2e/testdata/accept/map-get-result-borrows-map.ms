import expect_equal from "@std/test/test.ms"

fn find(m: Map[String, List[Int]], key: String) List[Int]?:
    return m.get(key)

test "a function returning Map.get reads the entry in place":
    let m: Map[String, List[Int]] = {"a": [1, 2]}
    try expect_equal(find(m, "a").get().length(), 2)
    try expect_equal(find(m, "z").is_none(), true)

test "a clone of the result owns its copy":
    var m: Map[String, List[Int]] = {"a": [1]}
    let found = find(m, "a").clone()
    m.add("b", [2])
    try expect_equal(found.is_some(), true)
