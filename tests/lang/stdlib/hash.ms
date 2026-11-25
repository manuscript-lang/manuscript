// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes from "@std/bytes.ms",
	panic from "@std/core.ms",
	Crc64,
	Crc64Polynomial,
	MapHash,
	crc64,
	fnv1_32,
	fnv1_64,
	fnv1a32,
	fnv1a64 from "@std/crypto/hash.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

test "FNV known vectors for both variants and widths" {
	expect_equal(fnv1a32(Bytes([])).to_int(), 2166136261)?
	expect_equal(fnv1a32("a".to_bytes()).to_int(), 3826002220)?
	expect_equal(fnv1_32("a".to_bytes()).to_int(), 84696446)?
	expect_equal(fnv1a64("a".to_bytes()).to_string(), "12638187200555641996")?
	expect_equal(fnv1_64("a".to_bytes()).to_string(), "12638153115695167422")?
	expect_equal(fnv1a64(Bytes([])).to_string(), "14695981039346656037")?
}

test "CRC64 matches the standard check values" {
	input := "123456789".to_bytes()
	expect_equal(crc64(Crc64Polynomial.Ecma, input).to_string(), "11051210869376104954")?
	expect_equal(crc64(Crc64Polynomial.Iso, input).to_string(), "13333283586479230977")?
	expect_equal(crc64(Crc64Polynomial.Ecma, Bytes([])).to_string(), "0")?
}

test "CRC64 chunks equal one pass" {
	var sum = Crc64(polynomial: Crc64Polynomial.Ecma)
	sum.update("1234".to_bytes())
	sum.update("56789".to_bytes())
	expect_equal(sum.value().to_string(), "11051210869376104954")?
}

test "seeded hash is deterministic per seed and differs between seeds" {
	left := MapHash(seed: 1)
	right := MapHash(seed: 2)
	expect_equal(
		left.hash("key".to_bytes()).to_string(),
		left.hash_string("key").to_string(),
	)?
	expect_true(left.hash_string("key") != right.hash_string("key"))?
	expect_true(left.hash_string("key") != left.hash_string("kez"))?
}

test "CRC64 table paths equal the bitwise path" {
	for polynomial in [Crc64Polynomial.Ecma, Crc64Polynomial.Iso] {
		for length in [255, 256, 257, 4095, 4096, 4103, 9001] {
			var raw List[UInt8] = []
			for index in 0..length {
				raw.append(
					(
						(index * 73 + index / 7)
						% 256
					).to_uint8() or panic("called Optional.get() on null")
				)
			}

			data := Bytes(raw.clone())
			var chunked = Crc64(polynomial: polynomial)
			var chunk List[UInt8] = []

			for byte in raw {
				chunk.append(byte)

				if chunk.length() == 100 {
					chunked.update(Bytes(chunk))
					chunk = []
				}
			}

			chunked.update(Bytes(chunk))
			expect_equal(
				crc64(polynomial, data).to_string(),
				chunked.value().to_string(),
			)?
		}
	}
}
// expect-exit: 0
// expect-tests: passed=5 failed=0
