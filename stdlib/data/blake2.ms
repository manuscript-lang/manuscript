import Bytes, BytesBuilder from "@std/bytes.ms"
import panic from "@std/core.ms"
import (
    bit_and,
    bit_or,
    bit_xor,
    rotate_right,
    shift_left,
    shift_right_unsigned,
    wrapping_add
) from "@std/math/math.ms"

# Message word schedule shared by BLAKE2b (12 rounds, rows 0-9 then 0-1 again) and BLAKE2s (10 rounds).
fn sigma() List[List[Int]]:
    return [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]
    ]

# Reads a little-endian word of `width` bytes at `at`, zero padding past the end of `data`.
fn word(data: Bytes, at: Int, width: Int) Int:
    var value = 0

    for offset in 0..width:
        let index = at + offset
        if index < data.length():
            value = bit_or(value, shift_left(data.get(index).to_int(), 8 * offset))

    return value

# The padded input: the key block (if any) followed by the data, zero filled to a whole number of blocks (at least one).
fn padded(key: Bytes, data: Bytes, block: Int) Bytes:
    var out = BytesBuilder()

    if key.length() > 0:
        out.append_bytes(key)
        for fill in key.length()..block:
            out.append(0)

    out.append_bytes(data)

    var written = data.length()
    if key.length() > 0:
        written = block + data.length()

    var fill_to = ((written + block - 1) / block) * block
    if fill_to == 0:
        fill_to = block
    for fill in written..fill_to:
        out.append(0)
    return out.build()

fn check(length: Int, key: Bytes, max: Int) Unit:
    if length < 1 or length > max:
        panic("blake2: digest length must be 1 through {max}")
    if key.length() > max:
        panic("blake2: key must be at most {max} bytes")

# Returns the BLAKE2b digest (RFC 7693) of `data`, optionally keyed, of `length` bytes.
# `length` is 1 through 64 and `key` at most 64 bytes; a violation faults. An empty key is unkeyed.
# `blake2b("abc".to_bytes())` begins with the bytes ba80a53f981c4d0d.
export fn blake2b(data: Bytes, key: Bytes = Bytes([]), length: Int = 64) Bytes:
    check(length, key, 64)

    let iv = [
        7640891576956012808, -4942790177534073029, 4354685564936845355,
        -6534734903238641935, 5840696475078001361, -7276294671716946913,
        2270897969802886507, 6620516959819538809
    ]
    var h = iv.clone()
    h.set(0, bit_xor(h.get(0), 16842752 + key.length() * 256 + length))

    let message = padded(key, data, 128)
    let blocks = message.length() / 128
    let schedule = sigma()
    var total = data.length()
    if key.length() > 0:
        total += 128

    var counted = 0

    for block in 0..blocks:
        let last = block == blocks - 1

        if last:
            counted = total
        else:
            counted = (block + 1) * 128

        var m: List[Int] = []
        for index in 0..16:
            m.append(word(message, block * 128 + index * 8, 8))

        var v = h.clone()
        for index in 0..8:
            v.append(iv.get(index))
        v.set(12, bit_xor(v.get(12), counted))
        if last:
            v.set(14, bit_xor(v.get(14), -1))

        for round in 0..12:
            let s = schedule.get(round % 10)

            for step in 0..8:
                var a = step % 4
                var b = 4 + step % 4
                var c = 8 + step % 4
                var d = 12 + step % 4
                var x = 0
                var y = 0

                if step < 4:
                    x = m.get(s.get(2 * step))
                    y = m.get(s.get(2 * step + 1))
                else:
                    b = 4 + (step + 1) % 4
                    c = 8 + (step + 2) % 4
                    d = 12 + (step + 3) % 4
                    x = m.get(s.get(2 * step))
                    y = m.get(s.get(2 * step + 1))

                var va = v.get(a)
                var vb = v.get(b)
                var vc = v.get(c)
                var vd = v.get(d)
                va = wrapping_add(wrapping_add(va, vb), x)
                vd = rotate_right(bit_xor(vd, va), 32)
                vc = wrapping_add(vc, vd)
                vb = rotate_right(bit_xor(vb, vc), 24)
                va = wrapping_add(wrapping_add(va, vb), y)
                vd = rotate_right(bit_xor(vd, va), 16)
                vc = wrapping_add(vc, vd)
                vb = rotate_right(bit_xor(vb, vc), 63)
                v.set(a, va)
                v.set(b, vb)
                v.set(c, vc)
                v.set(d, vd)

        for index in 0..8:
            h.set(index, bit_xor(bit_xor(h.get(index), v.get(index)), v.get(index + 8)))

    var out = BytesBuilder()

    for index in 0..length:
        let w = h.get(index / 8)
        out.append(
            bit_and(
                shift_right_unsigned(w, 8 * (index % 8)), 255
            ).to_uint8().get(0)
        )

    return out.build()
