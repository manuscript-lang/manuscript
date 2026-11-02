import Bytes from "@std/bytes.ms"
import (
    bit_and,
    bit_xor,
    shift_right_unsigned,
    wrapping_multiply
) from "@std/math/math.ms"
import secure_int from "@std/os/random.ms"

# 64-bit state is held in an Int; this reads its bit pattern as an unsigned word.
fn unsigned(raw: Int) UInt64:
    let high = shift_right_unsigned(raw, 32).to_uint64().get(0)
    let low = bit_and(raw, 4294967295).to_uint64().get(0)
    return high * 4294967296 + low

# Hashes `data` with 32-bit FNV-1a (offset 2166136261, prime 16777619).
# These hashes spread keys over buckets; they detect nothing adversarial and authenticate nothing.
# `fnv1a32("a".to_bytes())` returns 3826002220 (0xE40C292C).
export fn fnv1a32(data: Bytes) UInt32:
    var hash = 2166136261
    for index in 0..data.length():
        hash = bit_and(
            wrapping_multiply(
                bit_xor(hash, data.get(index).to_int()), 16777619
            ),
            4294967295
        )
    return hash.to_uint32().get(0)

# Hashes `data` with 32-bit FNV-1, which multiplies before it mixes in each byte.
# `fnv1_32("a".to_bytes())` returns 84696446 (0x050C5D7E).
export fn fnv1_32(data: Bytes) UInt32:
    var hash = 2166136261
    for index in 0..data.length():
        hash = bit_xor(
            bit_and(wrapping_multiply(hash, 16777619), 4294967295),
            data.get(index).to_int()
        )
    return hash.to_uint32().get(0)

# Hashes `data` with 64-bit FNV-1a (offset 14695981039346656037, prime 1099511628211).
# `fnv1a64("a".to_bytes())` returns 12638187200555641996 (0xAF63DC4C8601EC8C).
export fn fnv1a64(data: Bytes) UInt64:
    var hash = -3750763034362895579
    for index in 0..data.length():
        hash = wrapping_multiply(bit_xor(hash, data.get(index).to_int()), 1099511628211)
    return unsigned(hash)

# Hashes `data` with 64-bit FNV-1, which multiplies before it mixes in each byte.
# `fnv1_64("a".to_bytes())` returns 12638153115695167422 (0xAF63BD4C8601B7BE).
export fn fnv1_64(data: Bytes) UInt64:
    var hash = -3750763034362895579
    for index in 0..data.length():
        hash = bit_xor(wrapping_multiply(hash, 1099511628211), data.get(index).to_int())
    return unsigned(hash)

# Selects the polynomial of a 64-bit cyclic redundancy check.
export type Crc64Polynomial:
    # CRC-64/XZ (ECMA-182, reflected 0xC96C5795D7870F42), as used by xz and Go's `crc64.ECMA`.
    case Ecma
    # CRC-64/GO-ISO (reflected 0xD800000000000000), Go's `crc64.ISO`.
    case Iso

impl Crc64Polynomial:
    # The reflected polynomial as an Int bit pattern.
    fn reflected() Int:
        match self:
            Ecma: return -3932672073523589310
            Iso: return -2882303761517117440

# A 64-bit CRC built from ordered chunks, retaining no input bytes. Initial register and final XOR are all ones.
# `var sum = Crc64(Crc64Polynomial.Ecma)` then `sum.update("123456789".to_bytes())` gives `sum.value()` = 11051210869376104954.
# Reading the value does not reset it. It detects accidental corruption; it does not authenticate data.
export type Crc64:
    # The polynomial this checksum uses.
    polynomial: Crc64Polynomial
    # Register state, stored complemented so the empty checksum is zero.
    state: Int = 0

impl Crc64:
    # Appends these bytes to the checksum; an empty chunk leaves it unchanged.
    var fn update(data: Bytes) Unit:
        let poly = self.polynomial.reflected()
        var crc = bit_xor(self.state, -1)

        for index in 0..data.length():
            crc = bit_xor(crc, data.get(index).to_int())

            for bit in 0..8:
                let low = bit_and(crc, 1)
                crc = shift_right_unsigned(crc, 1)
                if low == 1:
                    crc = bit_xor(crc, poly)

        self.state = bit_xor(crc, -1)

    # Returns the current checksum without resetting or otherwise changing it.
    fn value() UInt64:
        return unsigned(self.state)

# Computes the CRC-64 of `data` for `polynomial`.
# `crc64(Crc64Polynomial.Ecma, "123456789".to_bytes())` returns 11051210869376104954 (0x995DC9BBDF1939FA).
export fn crc64(polynomial: Crc64Polynomial, data: Bytes) UInt64:
    var sum = Crc64(polynomial: polynomial)
    sum.update(data)
    return sum.value()

# A seeded, non-cryptographic 64-bit hash for hash tables and sharding.
# Equal seeds hash equal bytes to equal values on every platform; `random_seed()` draws a fresh seed per call,
# so hash values are not stable across runs. Do not use it to authenticate data or defend against chosen input.
# `let seed = MapHash(seed: random_seed())` then `seed.hash("key".to_bytes())` buckets keys unpredictably.
export type MapHash:
    # The seed mixed into every hash.
    seed: Int

# Returns an unpredictable seed from the operating system.
export fn random_seed() Int:
    return secure_int(-9223372036854775807, none).get(0)

impl MapHash:
    # Hashes the bytes with this seed, finishing with a 64-bit avalanche so every output bit depends on all input bits.
    fn hash(data: Bytes) UInt64:
        var state = bit_xor(self.seed, -3750763034362895579)

        for index in 0..data.length():
            state = wrapping_multiply(
                bit_xor(state, data.get(index).to_int()), -7046029254386353131
            )
            state = bit_xor(state, shift_right_unsigned(state, 29))

        state = wrapping_multiply(
            bit_xor(state, shift_right_unsigned(state, 33)), -49064778989728563
        )
        state = wrapping_multiply(
            bit_xor(state, shift_right_unsigned(state, 33)), -4265267296055464877
        )
        return unsigned(bit_xor(state, shift_right_unsigned(state, 33)))

    # Hashes a string's UTF-8 bytes with this seed.
    fn hash_string(text: String) UInt64:
        return self.hash(text.to_bytes())
