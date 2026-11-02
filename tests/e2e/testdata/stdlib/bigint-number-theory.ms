import expect_equal, expect_true, expect_false from "@std/test/test.ms"
import (
    BigInt,
    BigIntError,
    binomial,
    factorial,
    from_int,
    parse
) from "@std/math/math.ms"

test "factorial and binomial are exact":
    try expect_equal((try factorial(0)).to_string_radix(10), "1")
    try expect_equal((try factorial(5)).to_string_radix(10), "120")
    try expect_equal(
        (try factorial(25)).to_string_radix(10), "15511210043330985984000000"
    )
    try expect_equal((try binomial(5, 2)).to_string_radix(10), "10")
    try expect_equal((try binomial(60, 30)).to_string_radix(10), "118264581564861424")
    try expect_equal((try binomial(5, 0)).to_string_radix(10), "1")
    try expect_equal((try binomial(5, 6)).to_string_radix(10), "0")
    try expect_equal(
        (try binomial(100, 50)).to_string_radix(10), "100891344545564193334812497256"
    )

test "factorial and binomial reject negative inputs":
    let bad: BigInt!BigIntError = error(BigIntError.InvalidInput)
    try expect_equal(factorial(-1), bad)
    try expect_equal(binomial(-1, 0), bad)
    try expect_equal(binomial(3, -1), bad)

test "probable primes":
    for p in [2, 3, 97, 101, 7919, 1000000007]:
        try expect_true(from_int(p).is_probable_prime())
    for c in [-7, 0, 1, 4, 100, 561, 1105, 1000000007 * 3]:
        try expect_false(from_int(c).is_probable_prime())

    let mersenne = (try from_int(2).pow(127)) - from_int(1)
    try expect_true(mersenne.is_probable_prime())
    try expect_false((mersenne - from_int(2)).is_probable_prime())

    let pseudoprime = try parse("3825123056546413051", 10)

    # A strong pseudoprime to the first nine prime bases: nine rounds are fooled, the default thirteen are not.
    try expect_true(pseudoprime.is_probable_prime(9))
    try expect_false(pseudoprime.is_probable_prime())

test "modular square roots":
    let p = from_int(13)
    let root = (try from_int(10).mod_sqrt(p)).get(from_int(-1))
    try expect_equal((root * root % p).to_int(), 10)

    let absent: BigInt?!BigIntError = ok(none)
    try expect_equal(from_int(5).mod_sqrt(p), absent)
    try expect_equal((try from_int(0).mod_sqrt(p)).get(from_int(-1)).to_int(), 0)

    let q = from_int(41)
    let other = (try from_int(-1).mod_sqrt(q)).get(from_int(-1))
    try expect_equal((other * other % q).to_int(), 40)

    let big_p = try parse("170141183460469231731687303715884105727", 10)
    let n = from_int(123456789)
    let square = n * n % big_p
    let big_root = (try square.mod_sqrt(big_p)).get(from_int(-1))
    try expect_equal((big_root * big_root % big_p).compare(square), 0)

    let invalid: BigInt?!BigIntError = error(BigIntError.InvalidInput)
    try expect_equal(from_int(2).mod_sqrt(from_int(8)), invalid)
    try expect_equal(from_int(2).mod_sqrt(from_int(2)), invalid)
