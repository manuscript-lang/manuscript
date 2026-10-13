# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import Result from "@std/result.ms"

# Errors returned when random input is invalid or entropy generation fails.
export type RandomError:
    case InvalidInput
    case LimitExceeded
    case Failed(message: String)

# A source of cryptographically secure random bytes.
export interface Entropy:
    fn bytes(count: Int) -> Result[Bytes, RandomError]

# Returns a secure integer at least `min` and below `max_exclusive` when supplied.
export fn secure_int(
    entropy: Entropy,
    min: Int,
    max_exclusive: Optional[Int] = none
) -> Result[Int, RandomError]:

# Creates a version-4 UUID using the supplied cryptographic entropy source.
export fn uuid_v4(entropy: Entropy) -> Result[String, RandomError]:

impl Error for RandomError:
    fn message() -> String:

# Returns the operating system's cryptographic entropy source.
export fn entropy() -> Entropy:
