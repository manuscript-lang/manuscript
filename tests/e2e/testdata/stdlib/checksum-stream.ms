import (
	Bytes from "@std/bytes.ms",
	HashAlgorithm, digest from "@std/crypto.ms",
	Crc64Polynomial, crc64, crc64_of from "@std/crypto/hash.ms",
	adler32, adler32_of, crc32, crc32_of from "@std/data/checksum.ms",
	ReadStream, Source from "@std/io/io.ms",
	expect_equal, fail from "@std/test/test.ms",
)

// Hands out the chunks in order, then ends.
type Chunks:
	data: Bytes
	size: Int
	at: Int

fn var Chunks.next() Bytes?!:
	if self.at >= self.data.length(): return ok(none)

	var end = self.at + self.size
	if end > self.data.length(): end = self.data.length()

	piece := self.data.slice(self.at, end)?
	self.at = end
	return ok(piece)

fn var Chunks.close() Unit!:
	return ok(unit)

fn chunked(data: Bytes, size: Int) ReadStream[Bytes]:
	return ReadStream[Bytes](Chunks(data, size, 0))

test "stream checksums match the whole-value functions under every chunk size":
	data := "123456789 and some more bytes to cross chunk boundaries".to_bytes()

	for size in [1, 3, 8, 100]:
		expect_equal(crc32_of(chunked(data.clone(), size))?, crc32(data.clone()))?
		expect_equal(adler32_of(chunked(data.clone(), size))?, adler32(data.clone()))?
		expect_equal(
			crc64_of(chunked(data.clone(), size), Crc64Polynomial.Ecma)?,
			crc64(Crc64Polynomial.Ecma, data.clone())
		)?

test "digest of a stream matches the hasher":
	data := "digest me in pieces".to_bytes()
	for algorithm in [
		HashAlgorithm.Md5, HashAlgorithm.Sha1, HashAlgorithm.Sha256,
		HashAlgorithm.Sha512
	]:
		for size in [1, 4, 64]:
			if (
				(
					digest(chunked(data.clone(), size), algorithm)?
				) != algorithm.digest(data.clone())
			): return fail("size {size}")

test "an empty stream has the empty checksum":
	expect_equal(crc32_of(chunked("".to_bytes(), 4))?, 0)?
	expect_equal(adler32_of(chunked("".to_bytes(), 4))?, 1)?
