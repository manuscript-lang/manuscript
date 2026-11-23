import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	sha256 from "@std/crypto/crypto.ms",
	base64_decode, base64_encode, hex_encode from "@std/data/encoding.ms",

	words from "./src/harness.ms",
)

fn build_packed() Bytes:
	var bb = BytesBuilder()
	for j in 0..25000:
		bb.append_int32_le(j.to_int32() or 0)
	return bb.build()

// The size of `words(20000).join(",")`, which the encodings below report their time per
// byte of.
type BenchData:
	blob: Bytes
	b64: String
	packed: Bytes

fn make_fixture() BenchData:
	blob := words(20000).join(",").to_bytes()
	b64 := base64_encode(blob)
	return BenchData(blob: blob, b64: b64, packed: build_packed())

bench "encoding.base64_encode" per 157689:
	base64_encode(fixture.blob).length()

bench "encoding.base64_decode" per 157689:
	base64_decode(fixture.b64).get_or(Bytes([])).length()

bench "encoding.hex_encode" per 157689:
	hex_encode(fixture.blob).length()

bench "crypto.sha256" per 157689:
	sha256(fixture.blob).length()

bench "bytes.builder" per 100000:
	var bb = BytesBuilder()
	for j in 0..100000:
		bb.append((j % 256).to_uint8() or 0)
	bb.build().length()

bench "bytes.read_int32_le" per 25000:
	var sum = 0
	for j in 0..25000:
		sum += fixture.packed.int32_le(j * 4).get_or(0).to_int()
	sum

bench "bytes.read_uint32_le" per 25000:
	var sum = 0
	for j in 0..25000:
		sum += fixture.packed.uint32_le(j * 4).get_or(0).to_int()
	sum

bench "bytes.append_int32_le" per 100000:
	var bb = BytesBuilder()
	for j in 0..100000:
		bb.append_int32_le(j.to_int32() or 0)
	bb.build().length()
