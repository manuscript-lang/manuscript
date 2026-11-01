import Bytes from "@std/bytes.ms"
import msstd_random_draw_int, msstd_random_draw_uuid, msstd_random_draw_float, msstd_random_draw_shuffle, msstd_random_draw_choice, msstd_random_entropy from "@std/internal/random.ms"

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
interface Entropy:
    # Returns exactly `count` unpredictable bytes, with `count` from 0 through 16 MiB (16777216).
    # A negative or larger count returns InvalidInput; a source failure returns Failed. The operating system source observes task cancellation between 64 KiB chunks.
    var fn bytes(count: Int) Bytes!RandomError

impl Error for RandomError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `random: <reason>`.
    fn message() String:
        match self:
            InvalidInput: return "random: invalid input"
            LimitExceeded: return "random: limit exceeded"
            Failed(message): return message.clone()

# Returns a secure integer at least `min` and below `max_exclusive` when supplied, from the operating system's entropy.
export fn secure_int(min: Int, max_exclusive: Int?) Int!RandomError:
    return msstd_random_draw_int(msstd_random_entropy(), min, max_exclusive)

# Creates a version-4 UUID from the operating system's entropy.
export fn uuid_v4() String!RandomError:
    return msstd_random_draw_uuid(msstd_random_entropy())

# Returns a secure Float at least 0.0 and below 1.0 with 53 random bits (JavaScript `Math.random`, but cryptographically secure).
export fn float() Float!RandomError:
    return msstd_random_draw_float(msstd_random_entropy())

# Shuffles the list in place with an unbiased Fisher-Yates shuffle and returns it.
export fn shuffle[T](values: List[T]) List[T]!RandomError:
    return msstd_random_draw_shuffle(msstd_random_entropy(), values)

# Returns a uniformly chosen item, or none for an empty list.
export fn choice[T](values: List[T]) T?!RandomError:
    return msstd_random_draw_choice(msstd_random_entropy(), values)

# Returns exactly `count` unpredictable bytes from the operating system, with `count` from 0 through 16 MiB (16777216).
# A negative or larger count returns InvalidInput; a source failure returns Failed. The call observes task cancellation between 64 KiB chunks.
export fn random_bytes(count: Int) Bytes!RandomError:
    var source = msstd_random_entropy()
    return source.bytes(count)
