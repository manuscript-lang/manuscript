import (
    Bytes, BytesBuilder from "@std/bytes.ms",
    base64_encode from "@std/data/encoding.ms",
    now from "@std/time.ms",
    panic from "@std/core.ms",
    bit_and,
    bit_xor,
    shift_left,
    shift_right_unsigned,
    wrapping_add,
    wrapping_multiply,
    cos,
    log,
    max_int,
    sqrt from "@std/math/math.ms",
    msstd_random_os_bytes,
    draw_int,
    draw_float,
    draw_shuffle,
    draw_choice,
    invalid_input from "@std/internal/random.ms",
)

// Returns a secure integer at least `min` and below `max_exclusive` when supplied, from the operating system's entropy.
// ms: effect std.random.read
export fn secure_int(min: Int, max_exclusive: Int?) Int!:
    return draw_int(min, max_exclusive)

/*
Creates a ULID: 26 uppercase Crockford Base32 characters holding the Unix time in milliseconds and 80 random bits.
ULIDs made later sort after earlier ones as strings; two made in the same millisecond are ordered randomly.
Example: `"01ARZ3NDEKTSV4RRFFQ69G5FAV"`. Entropy failures return an `Error`.
*/
// ms: effect std.random.read
// ms: effect std.clock.read
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
// ms: effect std.random.read
export fn token(size: Int = 32) String!:
    let data = try random_bytes(size)
    return ok(base64_encode(data, url_safe: true, padded: false))

// Returns a secure Float at least 0.0 and below 1.0 with 53 random bits from the operating system's entropy.
// ms: effect std.random.read
export fn float() Float!:
    return draw_float()

// Shuffles the list in place with an unbiased Fisher-Yates shuffle and returns it.
// ms: effect std.random.read
export fn shuffle[T](values: List[T]) List[T]!:
    return draw_shuffle(values)

// Returns a uniformly chosen item, or none for an empty list.
// ms: effect std.random.read
export fn choice[T](values: List[T]) T?!:
    return draw_choice(values)

// Returns `count` distinct positions' items chosen uniformly without replacement, in random order, as copies; the input is unchanged.
// A `count` outside 0 through the list length returns EINVAL.
// ms: effect std.random.read
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
// ms: effect std.random.read
export fn weighted_choice[T: Clonable](values: List[T], weights: List[Float]) T?!:
    if values.is_empty() and weights.is_empty(): return ok(none)

    let total = weight_total(values.length(), weights)
    if total == 0.0: return error(Error("random: invalid input", kind: "EINVAL"))

    let point = try float()
    return ok(values[weighted_position(weights, point, total)].clone())

fn positions(count: Int) List[Int]:
    var out: List[Int] = []
    for i in 0..count:
        out.append(i)
    return out

/*
Returns the total, or zero for an invalid length, weight or all-zero total. An infinite total is
valid when all individual weights are finite; selection scales it before use. A loop rather than
`List.sum`, because the collection extensions cannot be used by modules `math.ms` imports.
*/
fn weight_total(count: Int, weights: List[Float]) Float:
    if weights.length() != count: return 0.0

    var total = 0.0

    for weight in weights:
        if not (weight >= 0.0) or not weight.is_finite(): return 0.0

        total += weight

    return total

// Selects a positive-weight position from a unit draw, keeping ordinary sums on their original scale.
fn weighted_position(weights: List[Float], unit_draw: Float, total: Float) Int:
    if not total.is_finite() or total < 2.2250738585072014e-308:
        return scaled_weighted_position(weights, unit_draw)

    let point = unit_draw * total
    var running = 0.0
    var last = 0

    for i in 0..weights.length():
        if weights[i] > 0.0:
            running += weights[i]
            last = i
            if point < running: return i

    return last

// A largest-weight scale keeps an overflowing or subnormal total in a safe range, without allocation.
fn scaled_weighted_position(weights: List[Float], unit_draw: Float) Int:
    var scale = 0.0
    for weight in weights:
        if weight > scale:
            scale = weight

    var total = 0.0
    for weight in weights:
        total += weight / scale

    let point = unit_draw * total
    var running = 0.0
    var last = 0

    for i in 0..weights.length():
        if weights[i] > 0.0:
            running += weights[i] / scale
            last = i
            if point < running: return i

    return last

// Returns exactly `count` unpredictable bytes from the operating system, with `count` from 0 through 16 MiB (16777216).
// A negative or larger count returns EINVAL; a source failure returns EIO. The call observes task cancellation between 64 KiB chunks.
// ms: effect std.random.read
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

        // Checked before subtracting: `max_exclusive - min` overflows exactly when the range is wider than the largest Int.
        if min < 0 and max_exclusive > max_int + min:
            panic("random int: the range is wider than the largest Int")

        let span = max_exclusive - min

        while true:
            let bits = shift_right_unsigned(self.next_bits(), 1)
            let rest = bits % span

            // Redraw the few values past the last whole multiple of `span`, so none is likelier.
            if bits - rest <= max_int - (span - 1): return min + rest

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
        if values.is_empty(): return none

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
        if values.is_empty() and weights.is_empty(): return none

        let total = weight_total(values.length(), weights)
        if total == 0.0:
            panic(
                "random weighted_choice: weights must match the values, be finite and non-negative, and not all be zero"
            )

        let point = self.float()
        return values[weighted_position(weights, point, total)].clone()

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
