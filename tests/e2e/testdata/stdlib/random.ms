import {Entropy, RandomError, secure_int, uuid_v4, entropy} from "@std/random.ms"
import Bytes from "@std/bytes.ms"
import {filled} from "@std/collections.ms"
import panic from "@std/faults.ms"

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
    if ((try secure_int(Entropy(source), -2, 3)) != -2): return panic(
        "random lower bound"
    )
    if source.requested != 1: return panic("entropy byte count")
    if (try uuid_v4(Entropy(source))) != "00000000-0000-4000-8000-000000000000": return panic(
        "UUID version and variant"
    )
    if source.requested != 16: return panic("UUID entropy count")

test "random errors propagate and invalid ranges do not read entropy":
    let source = ZeroEntropy(0)
    let invalid: Result[Int, RandomError] = error(RandomError.InvalidInput)
    if (secure_int(Entropy(source), 3, 3) != invalid): return panic("empty range")
    if source.requested != 0: return panic("invalid range consumed entropy")

    let failed: Result[String, RandomError] = error(RandomError.Failed("source failed"))
    if uuid_v4(Entropy(FailedEntropy("source failed"))) != failed: return panic(
        "entropy error lost"
    )
    if (try entropy().bytes(16)).length() != 16: return panic("host entropy")

test "random accepts negative exclusive upper bounds":
    let source = ZeroEntropy(0)
    if ((try secure_int(Entropy(source), -3, -2)) != -3): return panic(
        "negative single-value range"
    )
    if ((try secure_int(Entropy(source), -10, -5)) != -10): return panic(
        "negative range"
    )
