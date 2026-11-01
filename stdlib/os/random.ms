import Bytes from "@std/bytes.ms"
import panic from "@std/core.ms"
import (bit_xor, shift_right_unsigned, wrapping_add, wrapping_multiply, max_int) from "@std/math/math.ms"
import (
    msstd_random_draw_int,
    msstd_random_draw_uuid,
    msstd_random_draw_float,
    msstd_random_draw_shuffle,
    msstd_random_draw_choice,
    msstd_random_entropy
) from "@std/internal/random.ms"

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

# A deterministic pseudo-random generator: the same seed always gives the same sequence, on every platform.
# It is not secure; use `secure_int`, `float`, `shuffle` and `choice` when the values must be unpredictable.
# `var rng = seeded(1)` then `rng.int(0, 10)` returns the same value on every run.
export type SeededRandom:
    # Internal state: the SplitMix64 counter, advanced on every draw.
    state: Int

# Returns a generator that starts from `seed`; equal seeds give equal sequences (SplitMix64).
export fn seeded(seed: Int) SeededRandom:
    return SeededRandom(state: seed)

impl SeededRandom:
    # Returns the next 64 random bits as a signed Int.
    var fn next_bits() Int:
        self.state = wrapping_add(self.state, -7046029254386353131)

        var z = self.state
        z = wrapping_multiply(
            bit_xor(z, shift_right_unsigned(z, 30)), -4658895280553007687
        )
        z = wrapping_multiply(
            bit_xor(z, shift_right_unsigned(z, 27)), -7723592293110705685
        )
        return bit_xor(z, shift_right_unsigned(z, 31))

    # Returns an Int at least `min` and below `max_exclusive`, uniformly. A `min` not below `max_exclusive`, or a range wider than the largest Int, faults.
    var fn int(min: Int, max_exclusive: Int) Int:
        if min >= max_exclusive:
            panic("random int: min must be below max_exclusive")

        let span = max_exclusive - min
        if span <= 0:
            panic("random int: the range is wider than the largest Int")

        while true:
            let bits = shift_right_unsigned(self.next_bits(), 1)
            let rest = bits % span

            # Redraw the few values past the last whole multiple of `span`, so none is likelier.
            if bits - rest <= max_int - (span - 1):
                return min + rest

        return min

    # Returns a Float at least 0.0 and below 1.0 with 53 random bits.
    var fn float() Float:
        let bits = shift_right_unsigned(self.next_bits(), 11)
        return bits.to_float() / 9007199254740992.0

    # Shuffles `values` with an unbiased Fisher-Yates shuffle and returns it.
    var fn shuffle[T](values: List[T]) List[T]:
        var out = values
        var index = out.length() - 1

        while index > 0:
            out.swap(index, self.int(0, index + 1))
            index -= 1

        return out

    # Returns a uniformly chosen item, or none for an empty list.
    var fn choice[T](values: List[T]) T?:
        if values.is_empty():
            return none

        return values.get(self.int(0, values.length()))
