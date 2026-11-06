import expect_equal from "@std/test/test.ms"

test "integer families share one set of operations":
    let a: Int8 = (-5).to_int8().get()
    try expect_equal(a.abs(), (5).to_int8().get())
    try expect_equal(a.sign(), -1)
    try expect_equal(a.compare((3).to_int8().get()), -1)
    try expect_equal(a.to_float(), -5.0)
    try expect_equal(a.to_string_radix(2), "-101")

    let u: UInt16 = (255).to_uint16().get()
    try expect_equal(u.to_string_radix(16), "ff")
    try expect_equal(u.compare(u), 0)
    try expect_equal((7).abs(), 7)
    try expect_equal((-7).sign(), -1)
    try expect_equal((3).compare(4), -1)
