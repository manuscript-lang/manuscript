# conform: tags=stdlib-bigint,stdlib-testing,testing,tier-stdlib,numbers
# conform: phase=test
import expect_equal, expect_true from "@std/test.ms"
import from_int, BigInt from "@std/math.ms"

test "big integer operators agree with the named methods":
    let a = from_int(-7)
    let b = from_int(3)
    try expect_equal((a + b).to_int(), -4)
    try expect_equal((a - b).to_int(), -10)
    try expect_equal((a * b).to_int(), -21)
    try expect_equal((a / b).to_int(), -2)
    try expect_equal((a % b).to_int(), -1)
    try expect_equal((-a).to_int(), 7)
    try expect_true(a * b == a.multiply(b))

test "big integer operators compare exactly":
    let a = from_int(2)
    let b = from_int(5)
    try expect_true(a < b)
    try expect_true(a <= a)
    try expect_true(b > a)
    try expect_true(b >= b)
    try expect_true(a != b)
    try expect_true(a == from_int(2))

test "big integer operators keep precision past 64 bits":
    var x = from_int(1)
    for i in 0..70:
        x = x * from_int(2)
    try expect_equal(x.to_int(), none)
    try expect_equal(x.to_string_radix(10), "1180591620717411303424")
