import (
	Bytes from "@std/bytes.ms",
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

test "FNV known vectors for both variants and widths":
	expect_equal(fnv1a32(Bytes([])).to_int(), 2166136261)?
	expect_equal(fnv1a32("a".to_bytes()).to_int(), 3826002220)?
	expect_equal(fnv1_32("a".to_bytes()).to_int(), 84696446)?
	expect_equal(fnv1a64("a".to_bytes()).to_string_radix(10), "12638187200555641996")?
	expect_equal(fnv1_64("a".to_bytes()).to_string_radix(10), "12638153115695167422")?
	expect_equal(fnv1a64(Bytes([])).to_string_radix(10), "14695981039346656037")?

test "CRC64 matches the standard check values":
	input := "123456789".to_bytes()
	expect_equal(
		crc64(Crc64Polynomial.Ecma, input).to_string_radix(10), "11051210869376104954"
	)?
	expect_equal(
		crc64(Crc64Polynomial.Iso, input).to_string_radix(10), "13333283586479230977"
	)?
	expect_equal(crc64(Crc64Polynomial.Ecma, Bytes([])).to_string_radix(10), "0")?

test "CRC64 chunks equal one pass":
	var sum = Crc64(polynomial: Crc64Polynomial.Ecma)
	sum.update("1234".to_bytes())
	sum.update("56789".to_bytes())
	expect_equal(sum.value().to_string_radix(10), "11051210869376104954")?

test "seeded hash is deterministic per seed and differs between seeds":
	left := MapHash(seed: 1)
	right := MapHash(seed: 2)
	expect_equal(
		left.hash("key".to_bytes()).to_string_radix(10),
		left.hash_string("key").to_string_radix(10)
	)?
	expect_true(left.hash_string("key") != right.hash_string("key"))?
	expect_true(left.hash_string("key") != left.hash_string("kez"))?
