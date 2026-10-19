# conform: tags=closures,control-flow,faults,formatter,interfaces,lists,modules,optional,parser,records,stdlib-bytes,stdlib-collections,stdlib-random,stdlib-testing,strings,testing,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/random.ms
import {expect_equal} from "@std/testing.ms"
import {Entropy, RandomError, secure_int, uuid_v4, entropy, float, shuffle, choice} from "@std/random.ms"
import Bytes from "@std/bytes.ms"
import {filled} from "@std/collections.ms"

type ZeroEntropy:
    requested: Int

impl Entropy for ZeroEntropy:
    fn bytes(count: Int) Result[Bytes, RandomError]:
        self.requested = count
        return ok(Bytes(filled(0, count).get()))

type FailedEntropy:
    message: String

impl Entropy for FailedEntropy:
    fn bytes(count: Int) Result[Bytes, RandomError]:
        return error(RandomError.Failed(self.message))

test "random algorithms call Manuscript entropy implementations":
    let source = ZeroEntropy(0)
    try expect_equal((try secure_int(Entropy(source), -2, 3)), -2)
    try expect_equal(source.requested, 1)
    try expect_equal(
        (try uuid_v4(Entropy(source))),
        "00000000-0000-4000-8000-000000000000"
    )
    try expect_equal(source.requested, 16)

test "random errors propagate and invalid ranges do not read entropy":
    let source = ZeroEntropy(0)
    let invalid: Result[Int, RandomError] = error(RandomError.InvalidInput)
    try expect_equal(secure_int(Entropy(source), 3, 3), invalid)
    try expect_equal(source.requested, 0)
    let failed: Result[String, RandomError] = error(RandomError.Failed("source failed"))
    try expect_equal(uuid_v4(Entropy(FailedEntropy("source failed"))), failed)
    try expect_equal((try entropy().bytes(16)).length(), 16)

test "random accepts negative exclusive upper bounds":
    let source = ZeroEntropy(0)
    try expect_equal((try secure_int(Entropy(source), -3, -2)), -3)
    try expect_equal((try secure_int(Entropy(source), -10, -5)), -10)

test "float shuffle and choice use the supplied entropy":
    let zero = ZeroEntropy(0)
    try expect_equal(try float(Entropy(value: zero)), 0.0)
    let sample = try float(entropy())
    try expect_equal(sample >= 0.0 and sample < 1.0, true)
    let values = [1, 2, 3, 4, 5]
    let shuffled = try shuffle(entropy(), values)
    try expect_equal(
        shuffled.sorted(fn(left: Int, right: Int) Int: left - right),
        [1, 2, 3, 4, 5]
    )
    try expect_equal(try choice(Entropy(value: zero), [7, 8, 9]), some(7))
    try expect_equal(try choice(entropy(), List[Int]()), none)
