import {expect_equal} from "@std/testing.ms"
import {Entropy, RandomError, secure_int, uuid_v4, entropy} from "@std/random.ms"
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
