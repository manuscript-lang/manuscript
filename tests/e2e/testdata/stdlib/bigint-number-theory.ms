import (
    expect_equal, expect_true, expect_false from "@std/test/test.ms",
    BigInt, binomial, factorial, from_int, parse from "@std/math/math.ms",
)

test "factorial and binomial are exact":
    try expect_equal((try factorial(0)).to_string_radix(10), "1")
    try expect_equal((try factorial(5)).to_string_radix(10), "120")
    try expect_equal(
        (try factorial(25)).to_string_radix(10), "15511210043330985984000000"
    )
    try expect_equal((try factorial(100)).to_string_radix(10).length(), 158)
    try expect_equal((try factorial(100)) / (try factorial(99)), from_int(100))
    try expect_equal((try binomial(5, 2)).to_string_radix(10), "10")
    try expect_equal((try binomial(60, 30)).to_string_radix(10), "118264581564861424")
    try expect_equal((try binomial(5, 0)).to_string_radix(10), "1")
    try expect_equal((try binomial(5, 6)).to_string_radix(10), "0")
    try expect_equal(
        (try binomial(100, 50)).to_string_radix(10), "100891344545564193334812497256"
    )

test "factorial and binomial reject negative inputs":
    let bad: BigInt! = error(Error("big integer: invalid input", kind: "EINVAL"))
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

    // Above 3.3e24 the rounds also use random bases, and counts above 25 are honoured.
    try expect_true(mersenne.is_probable_prime(40))

    let other = (try from_int(2).pow(89)) - from_int(1)
    try expect_false((mersenne * other).is_probable_prime(40))

    let pseudoprime = try parse("3825123056546413051", 10)

    // A strong pseudoprime to the first nine prime bases: nine rounds are fooled, the default thirteen are not.
    try expect_true(pseudoprime.is_probable_prime(9))
    try expect_false(pseudoprime.is_probable_prime())

test "modular square roots":
    let p = from_int(13)
    let root = (try from_int(10).mod_sqrt(p)).get(from_int(-1))
    try expect_equal((root * root % p).to_int(), 10)

    let absent: BigInt?! = ok(none)
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

    let invalid: BigInt?! = error(Error("big integer: invalid input", kind: "EINVAL"))
    try expect_equal(from_int(2).mod_sqrt(from_int(8)), invalid)
    try expect_equal(from_int(2).mod_sqrt(from_int(2)), invalid)

// p = 79 * 8 * product(odd primes through 997) + 1. The complete p - 1
// factorization below and Lucas witnesses certify primality without random tests.
fn nonresidue_boundary_factors() List[Int]:
    return [
        2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73,
        79, 83, 89, 97, 101, 103, 107, 109, 113, 127, 131, 137, 139, 149, 151, 157, 163,
        167, 173, 179, 181, 191, 193, 197, 199, 211, 223, 227, 229, 233, 239, 241, 251,
        257, 263, 269, 271, 277, 281, 283, 293, 307, 311, 313, 317, 331, 337, 347, 349,
        353, 359, 367, 373, 379, 383, 389, 397, 401, 409, 419, 421, 431, 433, 439, 443,
        449, 457, 461, 463, 467, 479, 487, 491, 499, 503, 509, 521, 523, 541, 547, 557,
        563, 569, 571, 577, 587, 593, 599, 601, 607, 613, 617, 619, 631, 641, 643, 647,
        653, 659, 661, 673, 677, 683, 691, 701, 709, 719, 727, 733, 739, 743, 751, 757,
        761, 769, 773, 787, 797, 809, 811, 821, 823, 827, 829, 839, 853, 857, 859, 863,
        877, 881, 883, 887, 907, 911, 919, 929, 937, 941, 947, 953, 967, 971, 977, 983,
        991, 997
    ]

fn nonresidue_boundary_prime() BigInt:
    var product = from_int(79 * 4)
    for factor in nonresidue_boundary_factors():
        product *= from_int(factor)
    return product + from_int(1)

test "large nonresidue modulus has a complete primality certificate":
    let p = nonresidue_boundary_prime()
    let one = from_int(1)
    let minus_one = p - one

    for factor in nonresidue_boundary_factors():
        var base = 2
        if factor == 2: base = 1013
        if factor == 3 or factor == 13 or factor == 37: base = 3

        let a = from_int(base)
        try expect_equal(try a.pow_mod(minus_one, p), one)

        let witness = (try a.pow_mod(minus_one / from_int(factor), p)) - one
        try expect_equal(witness.gcd(p), one)

test "modular square root searches beyond a thousand quadratic residues":
    let p = nonresidue_boundary_prime()

    for value in [4, -4]:
        let a = from_int(value)
        let root = (try a.mod_sqrt(p)).get(from_int(-1))
        try expect_true(root.sign() >= 0 and root.compare(p) < 0)
        try expect_equal((root * root - a) % p, from_int(0))

test "modular square root rejects a composite witnessed during search":
    // For 1729, candidates 2 through 6 give +1, then its factor 7 gives 742.
    // Moduli 9 and 25 give nonzero results outside +1 and -1 at candidate 2.
    let invalid: BigInt?! = error(Error("big integer: invalid input", kind: "EINVAL"))
    try expect_equal(from_int(1).mod_sqrt(from_int(1729)), invalid)
    try expect_equal(from_int(1).mod_sqrt(from_int(9)), invalid)
    try expect_equal(from_int(1).mod_sqrt(from_int(25)), invalid)
