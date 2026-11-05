import Bytes, BytesBuilder from "@std/bytes.ms"
import base64_encode_unpadded from "@std/data/encoding.ms"
import now from "@std/os/time.ms"
import panic from "@std/core.ms"
import (
    bit_and,
    bit_xor,
    shift_left,
    shift_right_unsigned,
    wrapping_add,
    wrapping_multiply,
    cos,
    log,
    max_int,
    sqrt
) from "@std/math/math.ms"
import (
    msstd_random_os_bytes,
    draw_int,
    draw_uuid,
    draw_float,
    draw_shuffle,
    draw_choice,
    invalid_input
) from "@std/internal/random.ms"

// Returns a secure integer at least `min` and below `max_exclusive` when supplied, from the operating system's entropy.
export fn secure_int(min: Int, max_exclusive: Int?) Int!:
    return draw_int(min, max_exclusive)

// Creates a version-4 UUID from the operating system's entropy.
export fn uuid_v4() String!:
    return draw_uuid()

/*
Creates a ULID: 26 uppercase Crockford Base32 characters holding the Unix time in milliseconds and 80 random bits.
ULIDs made later sort after earlier ones as strings; two made in the same millisecond are ordered randomly.
Example: `"01ARZ3NDEKTSV4RRFFQ69G5FAV"`. Entropy failures return an `Error`.
*/
export fn ulid() String!:
    let moment = now()
    let millis = moment.seconds * 1000 + moment.nanos / 1000000
    let noise = try random_bytes(10)
    var raw = BytesBuilder()
    for place in 0..6:
        raw.append(
            bit_and(
                shift_right_unsigned(millis, 8 * (5 - place)), 255
            ).to_uint8().get(0)
        )
    raw.append_bytes(noise)

    // 128 bits behind two zero bits make exactly 26 five-bit digits.
    let alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".chars()
    var out = ""
    var pending = 0
    var held = 2

    for byte in raw.build().values():
        pending = pending * 256 + byte.to_int()
        held += 8

        while held >= 5:
            let digit = bit_and(shift_right_unsigned(pending, held - 5), 31)
            out = "{out}{alphabet[digit]}"
            held -= 5
            pending = bit_and(pending, shift_left(1, held) - 1)

    return ok(out)

/*
Returns a random token of `size` bytes as unpadded URL-safe Base64.
The default 32 bytes (256 bits) is 43 characters. Use it for session ids, API keys and password-reset links.
`size` follows `random_bytes`: 0 through 16 MiB, otherwise EINVAL.
*/
export fn token(size: Int = 32) String!:
    let data = try random_bytes(size)
    return ok(base64_encode_unpadded(data, url_safe: true))

// Returns a secure Float at least 0.0 and below 1.0 with 53 random bits from the operating system's entropy.
export fn float() Float!:
    return draw_float()

// Shuffles the list in place with an unbiased Fisher-Yates shuffle and returns it.
export fn shuffle[T](values: List[T]) List[T]!:
    return draw_shuffle(values)

// Returns a uniformly chosen item, or none for an empty list.
export fn choice[T](values: List[T]) T?!:
    return draw_choice(values)

// Returns `count` distinct positions' items chosen uniformly without replacement, in random order, as copies; the input is unchanged.
// A `count` outside 0 through the list length returns EINVAL.
export fn sample[T: Clonable](values: List[T], count: Int) List[T]!:
    if count < 0 or count > values.length():
        return error(Error("random: invalid input", kind: "EINVAL"))

    var order = positions(values.length())
    var out: List[T] = []

    for i in 0..count:
        let at = try secure_int(i, values.length())
        order.swap(i, at)
        out.append(values[order[i]].clone())

    return ok(out)

// Returns an item chosen with probability proportional to its weight, or none for an empty list.
// `weights` must match `values` in length, hold no negative or non-finite weight, and not all be zero; otherwise this returns EINVAL.
export fn weighted_choice[T: Clonable](values: List[T], weights: List[Float]) T?!:
    if values.is_empty() and weights.is_empty():
        return ok(none)
    if not valid_weights(values.length(), weights):
        return error(Error("random: invalid input", kind: "EINVAL"))

    let point = try float() * weight_total(weights)
    return ok(values[weighted_position(weights, point)].clone())

fn positions(count: Int) List[Int]:
    var out: List[Int] = []
    for i in 0..count:
        out.append(i)
    return out

/*
Reports whether `weights` has `count` finite, non-negative entries with a positive total.
Sums the weights. A loop rather than `List.sum`, because `@std/math/math.ms` imports this module and the
modules the collection extensions import cannot use those extensions.
*/
fn weight_total(weights: List[Float]) Float:
    var total = 0.0
    for weight in weights:
        total += weight
    return total

fn valid_weights(count: Int, weights: List[Float]) Bool:
    if weights.length() != count:
        return false

    var total = 0.0

    for weight in weights:
        if not (weight >= 0.0) or not weight.is_finite():
            return false

        total += weight

    return total > 0.0 and total.is_finite()

// Returns the position whose share of the total weight contains `point`, which is at least 0.0 and below the total.
// Zero-weight positions are never returned.
fn weighted_position(weights: List[Float], point: Float) Int:
    var running = 0.0
    var last = 0

    for i in 0..weights.length():
        if weights[i] > 0.0:
            running += weights[i]
            last = i
            if point < running:
                return i

    return last

// Returns exactly `count` unpredictable bytes from the operating system, with `count` from 0 through 16 MiB (16777216).
// A negative or larger count returns EINVAL; a source failure returns EIO. The call observes task cancellation between 64 KiB chunks.
export fn random_bytes(count: Int) Bytes!:
    return msstd_random_os_bytes(count)

/*
A deterministic pseudo-random generator: the same seed always gives the same sequence, on every platform.
It is not secure; use `secure_int`, `float`, `shuffle` and `choice` when the values must be unpredictable.
`var rng = seeded(1)` then `rng.int(0, 10)` returns the same value on every run.
*/
export type SeededRandom:
    // Internal state: the SplitMix64 counter, advanced on every draw.
    state: Int

// Returns a generator that starts from `seed`; equal seeds give equal sequences (SplitMix64).
export fn seeded(seed: Int) SeededRandom:
    return SeededRandom(state: seed)

impl SeededRandom:
    // Returns the next 64 random bits as a signed Int.
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

    // Returns an Int at least `min` and below `max_exclusive`, uniformly. A `min` not below `max_exclusive`, or a range wider than the largest Int, faults.
    var fn int(min: Int, max_exclusive: Int) Int:
        if min >= max_exclusive:
            panic("random int: min must be below max_exclusive")

        let span = max_exclusive - min
        if span <= 0:
            panic("random int: the range is wider than the largest Int")

        while true:
            let bits = shift_right_unsigned(self.next_bits(), 1)
            let rest = bits % span

            // Redraw the few values past the last whole multiple of `span`, so none is likelier.
            if bits - rest <= max_int - (span - 1):
                return min + rest

        return min

    // Returns a Float at least 0.0 and below 1.0 with 53 random bits.
    var fn float() Float:
        let bits = shift_right_unsigned(self.next_bits(), 11)
        return bits.to_float() / 9007199254740992.0

    // Shuffles `values` with an unbiased Fisher-Yates shuffle and returns it.
    var fn shuffle[T](values: List[T]) List[T]:
        var out = values
        var index = out.length() - 1

        while index > 0:
            out.swap(index, self.int(0, index + 1))
            index -= 1

        return out

    // Returns a uniformly chosen item, or none for an empty list.
    var fn choice[T](values: List[T]) T?:
        if values.is_empty():
            return none

        return values.get(self.int(0, values.length()))

    // Returns `count` items chosen uniformly without replacement, in random order, as copies; `values` is unchanged.
    // A `count` outside 0 through the list length faults.
    var fn sample[T: Clonable](values: List[T], count: Int) List[T]:
        if count < 0 or count > values.length():
            panic("random sample: count must be from 0 to the list length")

        var order = positions(values.length())
        var out: List[T] = []

        for i in 0..count:
            order.swap(i, self.int(i, values.length()))
            out.append(values[order[i]].clone())

        return out

    // Returns an item chosen with probability proportional to its weight, or none for an empty list.
    // `weights` must match `values` in length, hold no negative or non-finite weight, and not all be zero; otherwise this faults.
    var fn weighted_choice[T: Clonable](values: List[T], weights: List[Float]) T?:
        if values.is_empty() and weights.is_empty():
            return none

        if not valid_weights(values.length(), weights):
            panic(
                "random weighted_choice: weights must match the values, be finite and non-negative, and not all be zero"
            )

        let point = self.float() * weight_total(weights)
        return values[weighted_position(weights, point)].clone()

    // Returns a standard normal Float (mean 0, standard deviation 1) using the Box-Muller transform.
    var fn normal() Float:
        let radius = sqrt(-2.0 * log(1.0 - self.float()))
        return radius * cos(6.283185307179586 * self.float())

    // Returns an exponentially distributed Float with rate 1 (mean 1), always positive or zero.
    var fn exponential() Float:
        return -log(1.0 - self.float())

    // Returns a shuffled list of the Ints 0 through `count - 1`. A negative `count` faults.
    var fn permutation(count: Int) List[Int]:
        if count < 0:
            panic("random permutation: count must not be negative")

        var items: List[Int] = []
        for index in 0..count:
            items.append(index)
        return self.shuffle(items)
