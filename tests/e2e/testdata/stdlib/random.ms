import {expect_equal, expect_ok} from "@std/testing.ms"
import {Entropy, RandomError, secure_int, uuid_v4, entropy} from "@std/random.ms"
import Bytes from "@std/bytes.ms"
import {filled} from "@std/collections.ms"

type ZeroEntropy:
    requested: Int

impl Entropy for ZeroEntropy:
    fn bytes(count: Int) -> Result[Bytes, RandomError]:
        self.requested = count

        let data = match filled(value: 0, count: count):
            ok(found): found
            error(cause): return error(RandomError.Failed(cause.message()))

        return ok(Bytes(data))

type FailedEntropy:
    message: String

impl Entropy for FailedEntropy:
    fn bytes(count: Int) -> Result[Bytes, RandomError]:
        return error(RandomError.Failed(self.message))

test "random algorithms call Manuscript entropy implementations":
    let source = ZeroEntropy(0)
    try expect_equal(
        (
            secure_int(
                entropy: Entropy(source),
                min: -2,
                max_exclusive: 3
            ) | try expect_ok
        ),
        (-2)
    )
    source.requested | try expect_equal(expected: 1)
    uuid_v4(Entropy(source)) | try expect_ok | try expect_equal(
        expected: "00000000-0000-4000-8000-000000000000"
    )
    source.requested | try expect_equal(expected: 16)

test "random errors propagate and invalid ranges do not read entropy":
    let source = ZeroEntropy(0)
    let invalid: Result[Int, RandomError] = error(RandomError.InvalidInput)
    secure_int(entropy: Entropy(source), min: 3, max_exclusive: 3) | try expect_equal(
        expected: invalid
    )
    source.requested | try expect_equal(expected: 0)
    let failed: Result[String, RandomError] = error(RandomError.Failed("source failed"))
    uuid_v4(Entropy(FailedEntropy("source failed"))) | try expect_equal(
        expected: failed
    )
    (entropy().bytes(16) | try expect_ok).length() | try expect_equal(expected: 16)

test "random accepts negative exclusive upper bounds":
    let source = ZeroEntropy(0)
    try expect_equal(
        (
            secure_int(
                entropy: Entropy(source),
                min: -3,
                max_exclusive: (-2)
            ) | try expect_ok
        ),
        (-3)
    )
    try expect_equal(
        (
            secure_int(
                entropy: Entropy(source),
                min: -10,
                max_exclusive: (-5)
            ) | try expect_ok
        ),
        (-10)
    )
