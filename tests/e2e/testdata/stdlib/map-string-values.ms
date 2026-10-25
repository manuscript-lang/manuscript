from "@std/testing.ms" import expect_equal, expect_true

test "String value maps use full slot stride for String and Int keys":
    var strings = Map[String, String]()
    var integers = Map[Int, String]()
    var index = 0

    for key in ["first", "second", "third", "fourth"]:
        strings.add(key.clone(), key.clone())
        integers.add(index, key.clone())
        index += 1

    index = 0

    for key in ["first", "second", "third", "fourth"]:
        try expect_true(strings.contains(key))
        try expect_equal(strings.get(key).get(), key)
        try expect_true(integers.contains(index))
        try expect_equal(integers.get(index).get(), key)
        index += 1

    strings.add("second", "updated")
    integers.add(1, "updated")
    try expect_equal(strings.get("second").get(), "updated")
    try expect_equal(integers.get(1).get(), "updated")
    strings.remove("third")
    integers.remove(2)
    try expect_true(not strings.contains("third"))
    try expect_true(not integers.contains(2))
    try expect_equal(strings.get("fourth").get(), "fourth")
    try expect_equal(integers.get(3).get(), "fourth")

    let long = "heap-owned value " + "0123456789".repeat(20).get()
    strings.add("third", long.clone())
    integers.add(2, long.clone())

    let string_copy = strings.clone()
    let integer_copy = integers.clone()
    strings.remove("third")
    integers.remove(2)
    try expect_equal(string_copy.get("third").get(), long)
    try expect_equal(integer_copy.get(2).get(), long)
    try expect_true(string_copy.contains("fourth"))
    try expect_true(integer_copy.contains(3))
