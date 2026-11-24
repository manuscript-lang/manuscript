import (
	Bytes from "@std/bytes.ms",
	blake2b from "@std/crypto/blake2.ms",
	sha256, sha512 from "@std/crypto/crypto.ms",
	Crc64Polynomial, crc64, fnv1a64 from "@std/crypto/hash.ms",
	adler32, crc32 from "@std/data/checksum.ms",
	base64_decode, base64_encode, hex_decode, hex_encode from "@std/data/encoding.ms",
	Instant, monotonic from "@std/time.ms",
)

fn lap(name String, t Instant) Void {
	print(f"{name} {monotonic().difference(t).to_milliseconds()}")
}

fn main() Void! {
	n := 64 * 1024 * 1024
	var raw = List[UInt8](reserve: n)
	var s = 12345

	for i in 0..n {
		s = (s * 1103515245 + 12345) % 2147483648
		raw.append(((s / 65536) % 256).to_uint8() or 0)
	}

	data := Bytes(raw)
	var t = monotonic()
	a := crc32(data)
	lap("crc32", t)
	t = monotonic()

	b := adler32(data)
	lap("adler32", t)
	t = monotonic()

	c := sha256(data)
	lap("sha256", t)
	t = monotonic()

	d := sha512(data)
	lap("sha512", t)
	t = monotonic()

	e := blake2b(data)
	lap("blake2b", t)
	t = monotonic()

	f := fnv1a64(data)
	lap("fnv1a64", t)
	t = monotonic()

	g := crc64(Crc64Polynomial.Iso, data)
	lap("crc64", t)
	t = monotonic()

	h := base64_encode(data)
	lap("b64enc", t)
	t = monotonic()

	i := base64_decode(h, max_bytes: null)?
	lap("b64dec", t)
	t = monotonic()

	j := hex_encode(data)
	lap("hexenc", t)
	t = monotonic()

	k := hex_decode(j, max_bytes: null)?
	lap("hexdec", t)
	print(
		f"{a} {b} {c.length()} {d.length()} {e.length()} {f} {g} {i.length()} {k.length()}"
	)
}
