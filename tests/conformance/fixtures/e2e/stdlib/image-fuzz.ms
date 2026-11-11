// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	crc32 from "@std/data/checksum.ms",
	hex_decode from "@std/data/encoding.ms",
	ColorMode,
	ImageFormat,
	Rgba,
	decode_image,
	encode_image,
	new_image from "@std/image/image.ms",
	expect_equal, fail from "@std/test/test.ms",

	jpeg_vectors from "./support/image-jpeg-vectors.ms",
	vectors from "./support/image-png-vectors.ms",
)

// Deterministic generator (Numerical Recipes LCG); the fuzz is reproducible from the
// seed.
type Rng:
	state: Int

fn var Rng.next(limit: Int) Int:
	self.state = (self.state * 1103515245 + 12345) % 2147483648
	return (self.state / 65536) % limit

// One random mutation of `data`: byte flips, truncation, extreme field values, or a
// spliced range.
fn mutate(data: Bytes, var rng: Rng) Bytes:
	n := data.length()
	if n == 0: return data.clone()

	kind := rng.next(6)
	var values = data.values()

	if kind == 0:
		for _flip in 0..1 + rng.next(4):
			values[rng.next(n)] = rng.next(256).to_uint8().get(0)
	else if kind == 1:
		return data.slice(0, rng.next(n)).get(Bytes([]))
	else if kind == 2:
		at := rng.next(n)
		extremes := [0, 255, 127, 128, 1]
		for i in 0..4:
			if at + i < n: values[at + i] = extremes[rng.next(5)].to_uint8().get(0)
	else if kind == 3:
		// Drop a range.
		from := rng.next(n)
		to := min_int(n, from + 1 + rng.next(16))
		var kept = List[UInt8]()
		for i in 0..n:
			if i < from or i >= to: kept.append(values[i])
		return Bytes(kept)
	else if kind == 4:
		// Duplicate a range.
		from := rng.next(n)
		to := min_int(n, from + 1 + rng.next(16))
		var grown = List[UInt8]()

		for i in 0..n:
			grown.append(values[i])
			if i == to - 1:
				for j in from..to:
					grown.append(values[j])

		return Bytes(grown)
	else:
		// Header fields are the likeliest to be dangerous: hit the first 40 bytes.
		values[rng.next(min_int(n, 40))] = rng.next(256).to_uint8().get(0)

	return Bytes(values)

fn be32_at(values: List[UInt8], at: Int) Int:
	return (
		values[at].to_int() * 16777216
		+ values[at + 1].to_int() * 65536
		+ values[at + 2].to_int() * 256
		+ values[at + 3].to_int()
	)

// Rewrites every PNG chunk checksum so mutations reach the decoder past the CRC gate.
fn fix_png_crcs(data: Bytes) Bytes:
	var values = data.values()
	var at = 8

	while at + 12 <= values.length():
		length := be32_at(values, at)
		if length > values.length() - at - 12: break

		crc := crc32(data.slice(at + 4, at + 8 + length).get(Bytes([]))).to_int()
		post := at + 8 + length
		values[post] = (crc / 16777216 % 256).to_uint8().get(0)
		values[post + 1] = (crc / 65536 % 256).to_uint8().get(0)
		values[post + 2] = (crc / 256 % 256).to_uint8().get(0)
		values[post + 3] = (crc % 256).to_uint8().get(0)
		at = post + 4

	return Bytes(values)

fn min_int(a: Int, b: Int) Int:
	return if a < b: a else: b

fn seeds() List[Bytes]:
	var out = List[Bytes]()
	for v in vectors():
		out.append(hex_decode(v.png, none).get())
	for v in jpeg_vectors():
		out.append(hex_decode(v.jpeg, none).get())

	var img = new_image(5, 4, ColorMode.Rgba).get()
	img.set_pixel(1, 1, Rgba(9, 8, 7, 6))
	out.append(encode_image(img, ImageFormat.Bmp).get())
	out.append(
		encode_image(
			new_image(5, 4, ColorMode.Rgb).get(),
			ImageFormat.Ppm,
		).get()
	)
	out.append(
		encode_image(
			new_image(3, 3, ColorMode.Gray).get(),
			ImageFormat.Ppm,
		).get()
	)
	return out

test "decoders never fault on mutated input":
	var rng = Rng(20261109)
	corpus := seeds()
	var rejected = 0
	var accepted = 0

	for round in 0..300:
		for index in 0..corpus.length():
			var mutated = mutate(corpus[index], var rng)
			if mutated.starts_with(Bytes([137, 80, 78, 71])): mutated = fix_png_crcs(
				mutated
			)

			// The decoder must return a value, whatever the bytes. A fault aborts this
			// test.
			result := decode_image(mutated, max_pixels: 4000000)

			if result.is_ok():
				accepted += 1
			else:
				rejected += 1

	expect_equal(accepted + rejected, 300 * corpus.length())?
	print("fuzz: {accepted} accepted, {rejected} rejected")

fn expect_error(data: Bytes, kind: String) Unit!:
	result := decode_image(data)
	if result.is_ok(): return fail("expected {kind}, decoded an image")

	expect_equal(result.err().kind, kind)?

test "hostile headers fail before allocating":
	// PPM claiming 2^40 pixels with no raster.
	expect_error("P6\n1048576 1048576\n255\n".to_bytes(), "EOVERFLOW")?
	expect_error("P6\n99999999999999999999 1\n255\n".to_bytes(), "EOVERFLOW")?
	expect_error("P5\n40000 40000\n255\nx".to_bytes(), "EOVERFLOW")?

	// PNG IHDR 2^31-1 square, valid CRC, no pixel data.
	ihdr := hex_decode(
		"89504e470d0a1a0a0000000d494844527fffffff7fffffff0806000000",
		none,
	).get()
	expect_error(
		fix_png_crcs(ihdr.concat(Bytes([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))),
		"EOVERFLOW",
	)?

	// JPEG SOF 65535x65535 with a scan header and almost no data.
	jpeg := hex_decode(
		"ffd8ffdb004300"
		+ "01".repeat(64, none).get()
		+ "ffc0000b08ffffffff0101110000ffc400150000010000000000000000000000000000000000ffda0008010100003f00ffd9",
		none,
	).get()
	result := decode_image(jpeg)
	if result.is_ok(): fail("hostile JPEG decoded")?

	// BMP with a gigapixel header and no pixel data.
	bmp := hex_decode(
		"424d3600000000000000360000002800000000ca9a3b00ca9a3b0100180000000000000000000000000000000000000000000000",
		none,
	).get()
	bmp_result := decode_image(bmp)
	if bmp_result.is_ok(): fail("hostile BMP decoded")?
