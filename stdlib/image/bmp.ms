import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	Raster,
	bad,
	byte,
	pixel_count,
	too_big,
	unsupported,
	zeroed from "@std/image/codec.ms",
	bit_and, shift_left, shift_right_unsigned from "@std/math/math.ms",
)

// ---- BMP ----

fn le16(data: Bytes, at: Int) Int:
	return data.get(at).to_int() + data.get(at + 1).to_int() * 256

fn le32(data: Bytes, at: Int) Int:
	return le16(data, at) + le16(data, at + 2) * 65536

fn signed32(value: Int) Int:
	return if value >= 2147483648: value - 4294967296 else: value

fn mask_shift(mask: Int) Int:
	var shift = 0
	while bit_and(shift_right_unsigned(mask, shift), 1) == 0: shift += 1
	return shift

// Scales a bit-field channel with maximum `peak` to eight bits.
fn mask_channel(value: Int, shift: Int, peak: Int) Int:
	return (bit_and(shift_right_unsigned(value, shift), peak) * 255 + peak / 2) / peak

// Decodes an uncompressed BMP into a raster; `EBADMSG`, `ENOTSUP` or `EOVERFLOW` on
// failure.
export fn decode_bmp(data: Bytes, max_pixels: Int?) Raster!:
	if data.length() < 26: return error(bad("truncated BMP header"))

	offset := le32(data, 10)
	header := le32(data, 14)
	if (
		header != 12
		and header != 40
		and header != 52
		and header != 56
		and header != 108
		and header != 124
	):
		return error(unsupported("BMP header size {header}"))
	if data.length() < 14 + header: return error(bad("truncated BMP header"))

	var width = 0
	var height = 0
	var bits = 0
	var compression = 0
	var colors = 0

	if header == 12:
		width = le16(data, 18)
		height = le16(data, 20)
		bits = le16(data, 24)
	else:
		width = signed32(le32(data, 18))
		height = signed32(le32(data, 22))
		bits = le16(data, 28)
		compression = le32(data, 30)
		colors = le32(data, 46)

	top_down := height < 0
	if top_down: height = 0 - height

	// BI_BITFIELDS (3) carries explicit channel masks and applies to 32-bit pixels
	// only.
	if compression != 0 and (compression != 3 or bits != 32):
		return error(unsupported("BMP compression {compression}"))
	if bits != 1 and bits != 4 and bits != 8 and bits != 24 and bits != 32:
		return error(unsupported("BMP depth {bits}"))
	if width < 1 or width > 2147483647 or height > 2147483647:
		return error(bad("BMP dimensions out of range"))

	count := pixel_count(width, height, max_pixels)?

	// Palette entries sit between the header and the pixels.
	entry := if header == 12: 3 else: 4
	var palette_size = 0

	if bits <= 8:
		palette_size = if colors == 0: shift_left(1, bits) else: colors
		if palette_size > shift_left(1, bits): return error(
			bad("BMP palette too large")
		)

	// A 40-byte header stores its bit-field masks right after it; later headers include
	// them.
	bitfields := compression == 3
	palette_at := 14 + header + (if bitfields and header == 40: 12 else: 0)
	if bitfields and header < 40: return error(
		unsupported("BMP bit fields in a {header}-byte header")
	)
	if palette_at + palette_size * entry > data.length():
		return error(bad("truncated BMP palette"))

	row := ((width * bits + 31) / 32) * 4
	if offset < palette_at or offset > data.length(): return error(
		bad("BMP pixel offset out of range")
	)
	if height > (data.length() - offset) / row: return error(
		bad("truncated BMP pixel data")
	)

	// Masks in red, green, blue, alpha order; legacy 32-bit pixels are BGRA without a
	// mask.
	var masks = [0, 0, 0, 0]
	if bitfields: masks = [
		le32(data, 54),
		le32(data, 58),
		le32(data, 62),
		if header >= 56: le32(data, 66) else: 0,
	]

	var shifts = [0, 0, 0, 0]
	var peaks = [0, 0, 0, 0]

	for k in 0..4:
		if masks[k] != 0:
			shift := mask_shift(masks[k])
			peak := shift_right_unsigned(masks[k], shift)
			if bit_and(peak, peak + 1) != 0: return error(
				unsupported("BMP non-contiguous bit field")
			)

			shifts[k] = shift
			peaks[k] = peak

	if bitfields and (masks[0] == 0 or masks[1] == 0 or masks[2] == 0):
		return error(bad("BMP bit fields omit a color channel"))

	// Each channel needs bits of its own.
	for k in 1..4:
		for j in 0..k:
			if bit_and(masks[j], masks[k]) != 0: return error(
				bad("BMP bit fields overlap")
			)

	alpha := bits == 32 and (not bitfields or masks[3] != 0)
	m := if alpha: 4 else: 3
	var pixels = zeroed(count * m)
	var any_alpha = false

	for y in 0..height:
		source_row := if top_down: y else: height - 1 - y
		base := offset + source_row * row

		for x in 0..width:
			var r = 0
			var g = 0
			var b = 0
			var a = 255

			if bits == 24 or bits == 32:
				at := base + x * (bits / 8)

				if bitfields:
					v := le32(data, at)
					r = mask_channel(v, shifts[0], peaks[0])
					g = mask_channel(v, shifts[1], peaks[1])
					b = mask_channel(v, shifts[2], peaks[2])
					if alpha: a = mask_channel(v, shifts[3], peaks[3])
				else:
					b = data.get(at).to_int()
					g = data.get(at + 1).to_int()
					r = data.get(at + 2).to_int()

					if alpha:
						a = data.get(at + 3).to_int()
						if a != 0: any_alpha = true
			else:
				bit := x * bits
				shift := 8 - bits - bit % 8
				index := bit_and(
					shift_right_unsigned(
						data.get(base + bit / 8).to_int(),
						shift,
					),
					shift_left(1, bits) - 1,
				)
				if index >= palette_size: return error(
					bad("BMP palette index out of range")
				)

				p := palette_at + index * entry
				b = data.get(p).to_int()
				g = data.get(p + 1).to_int()
				r = data.get(p + 2).to_int()

			out := (y * width + x) * m
			pixels[out] = byte(r)
			pixels[out + 1] = byte(g)
			pixels[out + 2] = byte(b)
			if alpha: pixels[out + 3] = byte(a)

	// Legacy 32-bit BI_RGB alpha is often unused zero; treat an all-zero channel as
	// opaque. An explicit alpha mask is always honored.
	if alpha and not bitfields and not any_alpha:
		for i in 0..count:
			pixels[i * 4 + 3] = byte(255)
	return ok(Raster(width, height, m, pixels))

fn put16(var out: BytesBuilder, value: Int) Unit:
	out.append(byte(bit_and(value, 255)))
	out.append(byte(bit_and(shift_right_unsigned(value, 8), 255)))

fn put32(var out: BytesBuilder, value: Int) Unit:
	put16(var out, bit_and(value, 65535))
	put16(var out, bit_and(shift_right_unsigned(value, 16), 65535))

// Encodes pixels as a 24-bit BMP, or 32-bit with alpha; `EOVERFLOW` past BMP limits.
export fn encode_bmp(width: Int, height: Int, channels: Int, pixels: List[UInt8]) Bytes!:
	if width > 2147483647 or height > 2147483647:
		return error(too_big("BMP dimensions too large"))

	alpha := channels % 2 == 0
	bytes_per := if alpha: 4 else: 3

	// Alpha uses a 108-byte BITMAPV4HEADER with explicit masks so other readers see it.
	header := if alpha: 108 else: 40
	row := ((width * bytes_per * 8 + 31) / 32) * 4
	size := 14 + header + row * height
	if size > 4294967295: return error(too_big("BMP is larger than 4 GiB"))

	var out = BytesBuilder()
	out.append(byte(66))
	out.append(byte(77))
	put32(var out, size)
	put32(var out, 0)
	put32(var out, 14 + header)
	put32(var out, header)
	put32(var out, width)
	put32(var out, height)
	put16(var out, 1)
	put16(var out, bytes_per * 8)
	put32(var out, if alpha: 3 else: 0)
	put32(var out, row * height)
	put32(var out, 2835)
	put32(var out, 2835)
	put32(var out, 0)
	put32(var out, 0)

	if alpha:
		// Red, green, blue and alpha masks, then the color space and its unused fields.
		put32(var out, 16711680)
		put32(var out, 65280)
		put32(var out, 255)
		put32(var out, 4278190080)
		for _field in 0..13:
			put32(var out, 0)

	for y in 0..height:
		sy := height - 1 - y

		for x in 0..width:
			at := (sy * width + x) * channels
			red := pixels[at].to_int()
			green := if channels >= 3: pixels[at + 1].to_int() else: red
			blue := if channels >= 3: pixels[at + 2].to_int() else: red
			out.append(byte(blue))
			out.append(byte(green))
			out.append(byte(red))
			if alpha: out.append(pixels[at + channels - 1])

		for _pad in 0..row - width * bytes_per:
			out.append(byte(0))

	return ok(out.build())
