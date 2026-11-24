// ms: allow_effect std.random.read

// Non-cryptographic hashes and checksums: FNV, CRC-64 and a seeded hash for hash
// tables. They spread keys over buckets and detect accidental damage. For SHA-2, HMAC
// and other secure digests, see `@std/crypto/crypto.ms`.
import (
	Bytes from "@std/bytes.ms",
	ReadStream from "@std/io/io.ms",
	bit_and,
	bit_or,
	bit_xor,
	shift_left,
	shift_right_unsigned,
	wrapping_multiply from "@std/math/math.ms",
	secure_int from "@std/random.ms",
)

/*
Hashes `data` with 32-bit FNV-1a (offset 2166136261, prime 16777619).
These hashes spread keys over buckets; they detect nothing adversarial and authenticate nothing.
`fnv1a32("a".to_bytes())` returns 3826002220 (0xE40C292C).
*/
export fn fnv1a32(data Bytes) UInt32 {
	var hash = 2166136261
	for index in 0..data.length() {
		hash = bit_and(
			wrapping_multiply(
				bit_xor(hash, data.get(index).to_int()),
				16777619,
			),
			4294967295,
		)
	}
	return hash.to_uint32() or 0
}

// Hashes `data` with 32-bit FNV-1, which multiplies before it XORs in each byte.
// `fnv1_32("a".to_bytes())` returns 84696446 (0x050C5D7E).
export fn fnv1_32(data Bytes) UInt32 {
	var hash = 2166136261
	for index in 0..data.length() {
		hash = bit_xor(
			bit_and(wrapping_multiply(hash, 16777619), 4294967295),
			data.get(index).to_int(),
		)
	}
	return hash.to_uint32() or 0
}

// Hashes `data` with 64-bit FNV-1a (offset 14695981039346656037, prime 1099511628211).
// `fnv1a64("a".to_bytes())` returns 12638187200555641996 (0xAF63DC4C8601EC8C).
export fn fnv1a64(data Bytes) UInt64 {
	var hash = -3750763034362895579
	for index in 0..data.length() {
		hash = wrapping_multiply(bit_xor(hash, data.get(index).to_int()), 1099511628211)
	}
	return unsigned(hash)
}

// Hashes `data` with 64-bit FNV-1, which multiplies before it XORs in each byte.
// `fnv1_64("a".to_bytes())` returns 12638153115695167422 (0xAF63BD4C8601B7BE).
export fn fnv1_64(data Bytes) UInt64 {
	var hash = -3750763034362895579
	for index in 0..data.length() {
		hash = bit_xor(wrapping_multiply(hash, 1099511628211), data.get(index).to_int())
	}
	return unsigned(hash)
}

// Selects the polynomial of a 64-bit cyclic redundancy check.
export enum Crc64Polynomial {
	// CRC-64/XZ (ECMA-182, reflected 0xC96C5795D7870F42), as used by xz and Go's
	// `crc64.ECMA`.
	Ecma
	// CRC-64/GO-ISO (reflected 0xD800000000000000), Go's `crc64.ISO`.
	Iso
}

// The reflected polynomial as an Int bit pattern.
fn Crc64Polynomial.reflected() Int {
	match self {
		Ecma => return -3932672073523589310
		Iso => return -2882303761517117440
	}
}

// Slicing tables for a reflected CRC-64: `tables[k * 256 + b]` is the register after
// byte `b` followed by `k` zero bytes. Building one table costs about as much as
// hashing 256 bytes bit by bit, so `count` is 1 for mid-size inputs.
fn crc64_tables(poly Int, count Int) List[Int] {
	var tables = [0].repeated(count * 256)

	for b in 0..256 {
		var crc = b

		for bit in 0..8 {
			low := bit_and(crc, 1)
			crc = shift_right_unsigned(crc, 1)
			if low == 1 {
				crc = bit_xor(crc, poly)
			}
		}

		tables[b] = crc
	}

	for k in 1..count {
		for b in 0..256 {
			prev := tables[(k - 1) * 256 + b]
			tables[k * 256 + b] = bit_xor(
				tables[bit_and(prev, 255)],
				shift_right_unsigned(prev, 8),
			)
		}
	}

	return tables
}

/*
A 64-bit CRC built from ordered chunks, retaining no input bytes. Initial register and final XOR are all ones.
`var sum = Crc64(Crc64Polynomial.Ecma)` then `sum.update("123456789".to_bytes())` gives `sum.value()` = 11051210869376104954.
Reading the value does not reset it. It detects accidental corruption; it does not authenticate data.
*/
export type Crc64 {
	// The polynomial this checksum uses.
	polynomial Crc64Polynomial
	// Register state, stored complemented so the empty checksum is zero.
	state Int = 0
}

// Appends these bytes to the checksum; an empty chunk leaves it unchanged.
fn var Crc64.update(data Bytes) Void {
	poly := self.polynomial.reflected()
	length := data.length()
	var crc = bit_xor(self.state, -1)
	var index = 0

	if length >= 256 {
		wide := length >= 4096
		var count = 1
		if wide {
			count = 8
		}

		tables := crc64_tables(poly, count)

		while wide and index + 8 <= length {
			// Eight bytes per step: the register absorbs eight bytes, then each byte's
			// table advances it through the bytes that follow in the block.
			var word = 0
			for k in 0..8 {
				word = bit_or(word, shift_left(data.get(index + k).to_int(), 8 * k))
			}
			crc = bit_xor(crc, word)

			var next = 0
			for k in 0..8 {
				next = bit_xor(
					next,
					tables[
						(7 - k) * 256 + bit_and(
							shift_right_unsigned(
								crc,
								8 * k,
							),
							255,
						)
					],
				)
			}
			crc = next
			index += 8
		}

		while index < length {
			crc = bit_xor(
				tables[
					bit_and(
						bit_xor(crc, data.get(index).to_int()),
						255,
					)
				],
				shift_right_unsigned(crc, 8),
			)
			index += 1
		}
	} else {
		while index < length {
			crc = bit_xor(crc, data.get(index).to_int())

			for bit in 0..8 {
				low := bit_and(crc, 1)
				crc = shift_right_unsigned(crc, 1)
				if low == 1 {
					crc = bit_xor(crc, poly)
				}
			}

			index += 1
		}
	}

	self.state = bit_xor(crc, -1)
}

// Returns the current checksum without resetting or otherwise changing it.
fn Crc64.value() UInt64 {
	return unsigned(self.state)
}

// Computes the CRC-64 of `data` for `polynomial`.
// `crc64(Crc64Polynomial.Ecma, "123456789".to_bytes())` returns 11051210869376104954 (0x995DC9BBDF1939FA).
export fn crc64(polynomial Crc64Polynomial, data Bytes) UInt64 {
	var sum = Crc64(polynomial: polynomial)
	sum.update(data)
	return sum.value()
}

/*
A seeded, non-cryptographic 64-bit hash for hash tables and sharding.
Equal seeds hash equal bytes to equal values on every platform; `random_seed()` draws a fresh seed per call,
so hash values are not stable across runs. Do not use it to authenticate data or defend against chosen input.
`table_hash := MapHash(seed: random_seed())` then `table_hash.hash("key".to_bytes())` buckets keys unpredictably.
*/
export type MapHash {
	// The seed mixed into every hash.
	seed Int
}

// Hashes the bytes with this seed. A final 64-bit avalanche step makes every output
// bit depend on all input bits.
fn MapHash.hash(data Bytes) UInt64 {
	var state = bit_xor(self.seed, -3750763034362895579)

	for index in 0..data.length() {
		state = wrapping_multiply(
			bit_xor(state, data.get(index).to_int()),
			-7046029254386353131,
		)
		state = bit_xor(state, shift_right_unsigned(state, 29))
	}

	state = wrapping_multiply(
		bit_xor(state, shift_right_unsigned(state, 33)),
		-49064778989728563,
	)
	state = wrapping_multiply(
		bit_xor(state, shift_right_unsigned(state, 33)),
		-4265267296055464877,
	)
	return unsigned(bit_xor(state, shift_right_unsigned(state, 33)))
}

// Hashes a string's UTF-8 bytes with this seed.
fn MapHash.hash_string(text String) UInt64 {
	return self.hash(text.to_bytes())
}

// Returns an unpredictable seed from the operating system.
export fn random_seed() Int {
	return secure_int(-9223372036854775807).get_or(0)
}

/*
Reads `input` to the end and returns the CRC-64 of all its bytes with the given polynomial, as `crc64` does for
bytes in hand. Retains no input bytes, and consumes and closes the stream. A failed read returns its error.
*/
export fn crc64_of(move input ReadStream[Bytes], polynomial Crc64Polynomial) UInt64! {
	var sum = Crc64(polynomial: polynomial)
	var source = input
	for chunk in source {
		sum.update(chunk)
	}
	source.close()?
	return ok(sum.value())
}

// 64-bit state is held in an Int; this reads its bit pattern as an unsigned word.
fn unsigned(raw Int) UInt64 {
	high := shift_right_unsigned(raw, 32).to_uint64() or 0
	low := bit_and(raw, 4294967295).to_uint64() or 0
	return high * 4294967296 + low
}
