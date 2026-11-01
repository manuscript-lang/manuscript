import expect_equal from "@std/test/test.ms"

fn scaled(x: Int8) Int8:
    return (1 + 2) * x

test "arithmetic over literals takes the expected sized type":
    let a: Float32 = 0.1 + 0.2
    try expect_equal(a.to_float(), 0.30000001192092896)

    let b: Int8 = 100 + 27
    try expect_equal(b.to_int(), 127)

    let c: Int8 = -(60 + 67)
    try expect_equal(c.to_int(), -127)

    let d: Float32 = 1.0 / 3.0
    try expect_equal(d.to_float(), 0.3333333432674408)

test "literal arithmetic beside a sized operand adopts its type":
    try expect_equal(scaled(5).to_int(), 15)

    let y: Float32 = 2.0
    try expect_equal((y + 0.5 * 3.0).to_float(), 3.5)
