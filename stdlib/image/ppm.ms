import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	Raster, bad, byte, min_of, pixel_count, too_big from "@std/image/codec.ms",
)

// ---- PPM / PGM ----

fn is_space(b: Int) Bool:
	return b == 32 or b == 9 or b == 10 or b == 13 or b == 11 or b == 12

// Reads one header integer from `at`, skipping whitespace and # comments; returns
// (value, next offset).
fn ppm_number(data: Bytes, start: Int) List[Int]!:
	var at = start

	while at < data.length():
		b := data.get(at).to_int()

		if b == 35:
			while at < data.length() and data.get(at).to_int() != 10:
				at += 1
		else if is_space(b):
			at += 1
		else:
			break

	var value = 0
	var digits = 0

	while at < data.length():
		b := data.get(at).to_int()
		if b < 48 or b > 57: break

		value = value * 10 + b - 48
		if value > 4294967295: return error(too_big("header number too large"))

		digits += 1
		at += 1

	if digits == 0: return error(bad("expected a number in the PNM header"))

	return ok([value, at])

// Decodes binary PGM (P5) or PPM (P6) into a raster; `EBADMSG`, `ENOTSUP` or
// `EOVERFLOW` on failure.
export fn decode_ppm(data: Bytes, max_pixels: Int?) Raster!:
	if data.length() < 2: return error(bad("truncated PNM header"))

	kind := data.get(1).to_int()
	n := if kind == 54: 3 else: 1
	wide := ppm_number(data, 2)?
	tall := ppm_number(data, wide[1])?
	peak := ppm_number(data, tall[1])?
	width := wide[0]
	height := tall[0]
	maxval := peak[0]
	if maxval < 1 or maxval > 65535: return error(
		bad("PNM maxval {maxval} out of range")
	)

	// Exactly one whitespace byte separates the header from the raster.
	start := peak[1] + 1
	if peak[1] >= data.length() or not is_space(data.get(peak[1]).to_int()):
		return error(bad("missing separator after PNM header"))

	count := pixel_count(width, height, max_pixels)?
	sample := if maxval > 255: 2 else: 1

	// The raster must be present in full before anything is allocated.
	if count > (data.length() - start) / (n * sample): return error(
		bad("truncated PNM raster")
	)

	total := count * n
	var pixels = List[UInt8](reserve: total)

	for i in 0..total:
		at := start + i * sample

		// Two-byte samples are big-endian.
		var raw = data.get(at).to_int()
		if sample == 2: raw = raw * 256 + data.get(at + 1).to_int()

		if maxval == 255:
			pixels.append(byte(raw))
		else:
			pixels.append(byte((min_of(raw, maxval) * 255 + maxval / 2) / maxval))

	return ok(Raster(width, height, if n == 3: 3 else: 1, pixels))

// Encodes gray or RGB pixels as P5 or P6; `EINVAL` for alpha.
export fn encode_ppm(width: Int, height: Int, channels: Int, pixels: List[UInt8]) Bytes!:
	if channels % 2 == 0:
		return error(
			Error(
				"image: PNM cannot store alpha; convert to Rgb or Gray first",
				kind: "EINVAL",
			)
		)

	var out = BytesBuilder()
	magic := if channels == 3: "P6" else: "P5"
	out.append_bytes("{magic}\n{width} {height}\n255\n".to_bytes())
	for b in pixels:
		out.append(b)
	return ok(out.build())
