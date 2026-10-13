# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import List from "@std/collections.ms"

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

# Returns a secure binary64 value in [0, 1), using 53 unbiased random bits.
export fn secure_float(entropy: Entropy) -> Result[Float, RandomError]:

# Selects a secure random element, or none for an empty list without reading entropy.
export fn secure_choice[T](
    entropy: Entropy,
    values: List[T]
) -> Result[Optional[T], RandomError]:

# Returns a fresh shallow list in a secure Fisher–Yates random order.
export fn secure_shuffle[T](
    entropy: Entropy,
    values: List[T]
) -> Result[List[T], RandomError]:

# Mutable, reproducible SplitMix64 state for simulations and tests; unsuitable for secrets.
export type Random:
    # Samples a signed integer in [min, max_exclusive); none uses Int's maximum. InvalidInput reports min >= max_exclusive.
    fn int(
        min: Int,
        max_exclusive: Optional[Int] = none
    ) -> Result[Int, RandomError]:
    # Returns a binary64 value in [0, 1), using the next word's highest 53 bits.
    fn float() -> Float:
    # Selects an element, or none for an empty list without advancing state.
    fn choice[T](values: List[T]) -> Optional[T]:
    # Returns a fresh shallow Fisher–Yates permutation, preserving the input list.
    fn shuffle[T](values: List[T]) -> List[T]:

# Initializes SplitMix64 from the seed's 64-bit two's-complement representation.
export fn seeded(seed: Int) -> Random:

# Creates a version-4 UUID using the supplied cryptographic entropy source.
export fn uuid_v4(entropy: Entropy) -> Result[String, RandomError]:

impl Error for RandomError:
    fn message() -> String:

# Returns the operating system's cryptographic entropy source.
export fn entropy() -> Entropy:
