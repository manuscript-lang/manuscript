# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"

# Errors returned when random input is invalid or entropy generation fails.
export type RandomError:
    # The requested byte count is negative or above 16 MiB, or `secure_int` was given `min` not below `max_exclusive`.
    case InvalidInput
    # Reserved for requests that exceed a configured random-generation budget; the current operations do not return it.
    case LimitExceeded
    # The entropy source could not produce bytes, or returned a different number of bytes than requested.
    case Failed(
        # The source's failure text, which `message()` returns verbatim.
        message: String
    )

# A source of cryptographically secure random bytes.
export interface Entropy:
    # Returns exactly `count` unpredictable bytes, with `count` from 0 through 16 MiB (16777216).
    # A negative or larger count returns InvalidInput; a source failure returns Failed. The operating system source observes task cancellation between 64 KiB chunks.
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
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `random: <reason>`.
    fn message() -> String:

# Returns the operating system's cryptographic entropy source.
export fn entropy() -> Entropy:
