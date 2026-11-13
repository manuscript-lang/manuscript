import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	crc32 from "@std/data/checksum.ms",
	Raster,
	bad,
	byte,
	pixel_count,
	too_big,
	unsupported,
	zeroed from "@std/image/codec.ms",
	CompressionFormat, compress, decompress from "@std/io/archive.ms",
	bit_and, shift_left, shift_right_unsigned from "@std/math/math.ms",
)

// ---- PNG ----

CHUNK_IHDR := 1229472850
CHUNK_PLTE := 1347179589
CHUNK_TRNS := 1951551059
CHUNK_IDAT := 1229209940
CHUNK_IEND := 1229278788

fn be32(data: Bytes, at: Int) Int:
	return (
		data.get(at).to_int() * 16777216
		+ data.get(at + 1).to_int() * 65536
		+ data.get(at + 2).to_int() * 256
		+ data.get(at + 3).to_int()
	)

// The seven Adam7 passes as [x start, y start, x step, y step]; non-interlaced is one
// pass.
fn png_passes(interlaced: Bool) List[List[Int]]:
	if not interlaced: return [[0, 0, 1, 1]]
	return [
		[0, 0, 8, 8],
		[4, 0, 8, 8],
		[0, 4, 4, 8],
		[2, 0, 4, 4],
		[0, 2, 2, 4],
		[1, 0, 2, 2],
		[0, 1, 1, 2],
	]

fn png_channels(color: Int) Int:
	if color == 0 or color == 3: return 1
	if color == 2: return 3
	if color == 4: return 2

	return 4

// Total filtered byte count for the image, or the first pass that cannot be sized.
fn png_raw_size(width: Int, height: Int, bits_per_pixel: Int, interlaced: Bool) Int:
	var total = 0

	for pass in png_passes(interlaced):
		pw := (width - pass[0] + pass[2] - 1) / pass[2]
		ph := (height - pass[1] + pass[3] - 1) / pass[3]
		if pw > 0 and ph > 0:
			total += ph * (1 + (pw * bits_per_pixel + 7) / 8)

	return total

fn paeth(a: Int, b: Int, c: Int) Int:
	p := a + b - c
	pa := abs_of(p - a)
	pb := abs_of(p - b)
	pc := abs_of(p - c)
	if pa <= pb and pa <= pc: return a
	if pb <= pc: return b

	return c

fn abs_of(value: Int) Int:
	return if value < 0: 0 - value else: value

// Decodes any PNG color type, bit depth and interlacing into a raster; `EBADMSG`,
// `ENOTSUP` or `EOVERFLOW` on failure.
export fn decode_png(data: Bytes, max_pixels: Int?) Raster!:
	if data.length() < 33: return error(bad("truncated PNG"))

	magic := [137, 80, 78, 71, 13, 10, 26, 10]
	for i in 0..8:
		if data.get(i).to_int() != magic[i]: return error(bad("not a PNG signature"))

	var width = 0
	var height = 0
	var depth = 0
	var color = 0
	var interlaced = false
	var palette = List[Int]()
	var transparency = List[Int]()
	var have_header = false
	var have_end = false
	var idat = BytesBuilder()
	var idat_seen = false
	var idat_closed = false
	var at = 8

	while at < data.length() and not have_end:
		if data.length() - at < 12: return error(bad("truncated PNG chunk"))

		length := be32(data, at)
		if length > data.length() - at - 12: return error(
			bad("PNG chunk longer than the file")
		)

		kind := be32(data, at + 4)
		body := at + 8
		if (
			be32(data, body + length) != crc32(
				data.view(at + 4, body + length)
			).to_int()
		):
			return error(bad("PNG chunk checksum mismatch"))
		if not have_header and kind != CHUNK_IHDR: return error(
			bad("PNG must start with IHDR")
		)

		if kind != CHUNK_IDAT and idat_seen: idat_closed = true

		if kind == CHUNK_IHDR:
			if have_header or length != 13: return error(bad("bad PNG header chunk"))

			width = be32(data, body)
			height = be32(data, body + 4)
			depth = data.get(body + 8).to_int()
			color = data.get(body + 9).to_int()
			if data.get(body + 10).to_int() != 0 or data.get(body + 11).to_int() != 0:
				return error(unsupported("PNG compression or filter method"))

			method := data.get(body + 12).to_int()
			if method > 1: return error(bad("PNG interlace method {method}"))

			interlaced = method == 1
			if width < 1 or height < 1 or width > 2147483647 or height > 2147483647:
				return error(bad("PNG dimensions out of range"))

			// Reject oversized images from the header alone, before reading any
			// further.
			_ := pixel_count(width, height, max_pixels)?
			have_header = true
		else if kind == CHUNK_PLTE:
			if idat_seen or length % 3 != 0 or length == 0 or length > 768:
				return error(bad("bad PNG palette"))

			palette = List[Int]()
			for i in 0..length:
				palette.append(data.get(body + i).to_int())
		else if kind == CHUNK_TRNS:
			if idat_seen: return error(bad("PNG transparency after pixel data"))

			transparency = List[Int]()
			for i in 0..length:
				transparency.append(data.get(body + i).to_int())
		else if kind == CHUNK_IDAT:
			if idat_closed: return error(
				bad("PNG pixel data chunks are not contiguous")
			)

			idat_seen = true
			idat.append_bytes(data.view(body, body + length))
		else if kind == CHUNK_IEND:
			have_end = true
		else if bit_and(data.get(at + 4).to_int(), 32) == 0:
			return error(unsupported("critical PNG chunk"))

		at = body + length + 4

	if not have_end or not idat_seen: return error(
		bad("truncated PNG: missing IDAT or IEND")
	)

	valid := (
		(
			color == 0
			and (
				depth == 1
				or depth == 2
				or depth == 4
				or depth == 8
				or depth == 16
			)
		)
		or (
			(color == 2 or color == 4 or color == 6)
			and (depth == 8 or depth == 16)
		)
		or (
			color == 3
			and (depth == 1 or depth == 2 or depth == 4 or depth == 8)
		)
	)
	if not valid: return error(
		bad("PNG color type {color} cannot have bit depth {depth}")
	)
	if width < 1 or height < 1 or width > 2147483647 or height > 2147483647:
		return error(bad("PNG dimensions out of range"))

	count := pixel_count(width, height, max_pixels)?
	if color == 3 and palette.is_empty(): return error(
		bad("indexed PNG without a palette")
	)

	samples := png_channels(color)
	bits_per_pixel := samples * depth
	expected := png_raw_size(width, height, bits_per_pixel, interlaced)

	// The inflate budget is the size the header implies, so a bomb stops at that bound.
	raw := decompress(idat.build(), CompressionFormat.Zlib, expected)?
	if raw.length() != expected: return error(
		bad("PNG pixel data is {raw.length()} bytes, expected {expected}")
	)

	// Output layout. A tRNS chunk adds alpha to gray, RGB and indexed images.
	keyed := not transparency.is_empty()
	var m = 4
	if color == 0: m = if keyed: 2 else: 1
	if color == 2: m = if keyed: 4 else: 3
	if color == 3: m = if keyed: 4 else: 3
	if color == 4: m = 2

	var pixels = zeroed(count * m)
	step := if bits_per_pixel < 8: 1 else: bits_per_pixel / 8
	top := shift_left(1, depth) - 1
	var pos = 0

	for pass in png_passes(interlaced):
		pw := (width - pass[0] + pass[2] - 1) / pass[2]
		ph := (height - pass[1] + pass[3] - 1) / pass[3]
		if pw < 1 or ph < 1: continue

		row_bytes := (pw * bits_per_pixel + 7) / 8
		var prev = [0].repeated(row_bytes)

		for row in 0..ph:
			filter := raw.get(pos).to_int()
			if filter > 4: return error(bad("PNG filter type {filter}"))

			var cur = [0].repeated(row_bytes)

			for i in 0..row_bytes:
				x := raw.get(pos + 1 + i).to_int()
				a := if i >= step: cur[i - step] else: 0
				b := prev[i]
				c := if i >= step: prev[i - step] else: 0
				var v = x

				if filter == 1: v = x + a
				else if filter == 2: v = x + b
				else if filter == 3: v = x + (a + b) / 2
				else if filter == 4: v = x + paeth(a, b, c)

				cur[i] = v % 256

			pos += 1 + row_bytes

			y := pass[1] + row * pass[3]

			for px in 0..pw:
				out := (y * width + pass[0] + px * pass[2]) * m

				if color == 3 or color == 0:
					var v = 0

					if depth == 16:
						v = cur[px * 2] * 256 + cur[px * 2 + 1]
					else if depth == 8:
						v = cur[px]
					else:
						bit := px * depth
						v = bit_and(
							shift_right_unsigned(
								cur[bit / 8],
								8 - depth - bit % 8,
							),
							top,
						)

					if color == 3:
						if v * 3 + 2 >= palette.length(): return error(
							bad(
								"PNG palette index {v} out of range"
							)
						)

						pixels[out] = byte(palette[v * 3])
						pixels[out + 1] = byte(palette[v * 3 + 1])
						pixels[out + 2] = byte(palette[v * 3 + 2])
						if keyed: pixels[out + 3] = byte(
							if v < transparency.length(): transparency[
								v
							] else: 255
						)
					else:
						level := if depth == 16: v / 256 else: (
							if depth == 8: v else: v * 255 / top
						)
						pixels[out] = byte(level)

						if keyed:
							key := if transparency.length() >= 2: transparency[0] * 256 + transparency[
								1
							] else: -1
							pixels[out + 1] = byte(if v == key: 0 else: 255)
				else:
					width_bytes := depth / 8
					for ch in 0..samples:
						pixels[out + ch] = byte(cur[(px * samples + ch) * width_bytes])

					if color == 2 and keyed:
						var hit = transparency.length() >= 6

						if hit:
							for ch in 0..3:
								sample := if depth == 16: cur[(px * 3 + ch) * 2] * 256 + cur[
									(
										px * 3
										+ ch
									) * 2 + 1
								] else: cur[px * 3 + ch]
								if (
									sample != transparency[
										ch * 2
									] * 256 + transparency[ch * 2 + 1]
								): hit = false

						pixels[out + 3] = byte(if hit: 0 else: 255)

			prev = cur

	return ok(Raster(width, height, m, pixels))

fn put_be32(var out: BytesBuilder, value: Int) Unit:
	out.append(byte(bit_and(shift_right_unsigned(value, 24), 255)))
	out.append(byte(bit_and(shift_right_unsigned(value, 16), 255)))
	out.append(byte(bit_and(shift_right_unsigned(value, 8), 255)))
	out.append(byte(bit_and(value, 255)))

fn png_chunk(var out: BytesBuilder, kind: String, body: Bytes) Unit:
	put_be32(var out, body.length())

	tag := kind.to_bytes()
	out.append_bytes(tag)
	out.append_bytes(body)
	put_be32(var out, crc32(tag.concat(body)).to_int())

// Filters one row with the type whose residuals have the smallest absolute sum (the
// usual heuristic).
fn filter_row(row: List[Int], prev: List[Int], step: Int) List[Int]:
	var best = List[Int]()
	var best_cost = -1

	for filter in 0..5:
		var out = List[Int](reserve: row.length() + 1)
		out.append(filter)

		var cost = 0

		for i in 0..row.length():
			a := if i >= step: row[i - step] else: 0
			b := prev[i]
			c := if i >= step: prev[i - step] else: 0
			var predicted = 0

			if filter == 1: predicted = a
			else if filter == 2: predicted = b
			else if filter == 3: predicted = (a + b) / 2
			else if filter == 4: predicted = paeth(a, b, c)

			residual := (row[i] - predicted + 256) % 256
			out.append(residual)
			cost += if residual < 128: residual else: 256 - residual

		if best_cost < 0 or cost < best_cost:
			best = out
			best_cost = cost

	return best

// Encodes pixels as an 8-bit PNG with per-row filtering; `EOVERFLOW` past PNG limits.
export fn encode_png(width: Int, height: Int, channels: Int, pixels: List[UInt8]) Bytes!:
	if width > 2147483647 or height > 2147483647:
		return error(too_big("PNG dimensions too large"))

	n := channels
	var color = 6
	if n == 1: color = 0
	if n == 2: color = 4
	if n == 3: color = 2

	var raw = BytesBuilder()
	row_bytes := width * n
	var prev = [0].repeated(row_bytes)

	for y in 0..height:
		var row = List[Int](reserve: row_bytes)
		for i in 0..row_bytes:
			row.append(pixels[y * row_bytes + i].to_int())
		for v in filter_row(row, prev, n):
			raw.append(byte(v))
		prev = row

	var header = BytesBuilder()
	put_be32(var header, width)
	put_be32(var header, height)
	header.append(byte(8))
	header.append(byte(color))
	header.append(byte(0))
	header.append(byte(0))
	header.append(byte(0))

	var out = BytesBuilder()
	out.append_bytes(Bytes([137, 80, 78, 71, 13, 10, 26, 10]))
	png_chunk(var out, "IHDR", header.build())

	packed := compress(raw.build(), CompressionFormat.Zlib)?
	png_chunk(var out, "IDAT", packed)
	png_chunk(var out, "IEND", Bytes([]))
	return ok(out.build())
