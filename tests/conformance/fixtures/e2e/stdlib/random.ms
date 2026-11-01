# conform: tags=closures,control-flow,faults,interfaces,lists,modules,optional,records,stdlib-bytes,stdlib-collections,stdlib-random,stdlib-testing,strings,testing,tier-io,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/random.ms
import expect_equal from "@std/test/test.ms"
import RandomError, secure_int, uuid_v4, float, shuffle, choice, random_bytes from "@std/os/random.ms"

test "random bytes returns the requested count and rejects out-of-range counts":
    try expect_equal((try random_bytes(16)).length(), 16)
    try expect_equal((try random_bytes(0)).length(), 0)
    let invalid: Int!RandomError = error(RandomError.InvalidInput)
    try expect_equal(random_bytes(-1).map(fn bytes: bytes.length()), invalid)

test "secure_int stays in range and rejects an empty range":
    let invalid: Int!RandomError = error(RandomError.InvalidInput)
    try expect_equal(secure_int(3, 3), invalid)
    try expect_equal((try secure_int(-2, 3)) >= -2 and (try secure_int(-2, 3)) < 3, true)
    try expect_equal((try secure_int(-3, -2)), -3)
    try expect_equal((try secure_int(-10, -5)) < -5, true)

test "uuid_v4 has the version and variant bits":
    let id = try uuid_v4()
    try expect_equal(id.length(), 36)
    try expect_equal(try id.slice(14, 15), "4")
    try expect_equal(["8", "9", "a", "b"].contains(try id.slice(19, 20)), true)

test "float shuffle and choice use operating system entropy":
    let sample = try float()
    try expect_equal(sample >= 0.0 and sample < 1.0, true)

    let shuffled = try shuffle([1, 2, 3, 4, 5])
    try expect_equal(
        shuffled.sorted(fn(left: Int, right: Int) Int: left - right), [1, 2, 3, 4, 5]
    )
    try expect_equal(try choice([7]), 7)
    try expect_equal(try choice(List[Int]()), none)
