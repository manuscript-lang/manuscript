import expect_equal from "@std/test/test.ms"

fn replace(var values: Map[Int, Int]) Int:
    values.add(1, 9)
    return 0

test "a default that changes the map runs after the lookup":
    var values = {1: 7}
    selected := values.get(1).get(replace(var values))
    try expect_equal(selected, 7)
    try expect_equal(values.get(1).get(), 9)

test "a missing key still takes the default":
    var values = {1: 7}
    try expect_equal(values.get(2).get(replace(var values)), 0)
