import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	byte, max_of, min_of, too_big from "@std/image/codec.ms",
	jpeg_clamp,
	jpeg_dct_matrix,
	jpeg_zeros,
	jpeg_zigzag from "@std/image/jpeg_tables.ms",
	bit_and,
	bit_or,
	shift_left,
	shift_right,
	shift_right_unsigned from "@std/math/math.ms",
)

// ---- JPEG encoder ----

jpeg_base_luma := [
	16, 11, 12, 14, 12, 10, 16, 14, 13, 14, 18, 17, 16, 19, 24, 40, 26, 24, 22, 22, 24,
	49, 35, 37, 29, 40, 58, 51, 61, 60, 57, 51, 56, 55, 64, 72, 92, 78, 64, 68, 87, 69,
	55, 56, 80, 109, 81, 87, 95, 98, 103, 104, 103, 62, 77, 113, 121, 112, 100, 120, 92,
	101, 103, 99
]
jpeg_base_chroma := [
	17, 18, 18, 24, 21, 24, 47, 26, 26, 47, 99, 66, 56, 66, 99, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
	99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
	99
]
jpeg_dc_luma_counts := [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0]
jpeg_dc_chroma_counts := [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0]
jpeg_dc_values := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
jpeg_ac_luma_counts := [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125]
jpeg_ac_luma_values := [
	1, 2, 3, 0, 4, 17, 5, 18, 33, 49, 65, 6, 19, 81, 97, 7, 34, 113, 20, 50, 129, 145,
	161, 8, 35, 66, 177, 193, 21, 82, 209, 240, 36, 51, 98, 114, 130, 9, 10, 22, 23, 24,
	25, 26, 37, 38, 39, 40, 41, 42, 52, 53, 54, 55, 56, 57, 58, 67, 68, 69, 70, 71, 72,
	73, 74, 83, 84, 85, 86, 87, 88, 89, 90, 99, 100, 101, 102, 103, 104, 105, 106, 115,
	116, 117, 118, 119, 120, 121, 122, 131, 132, 133, 134, 135, 136, 137, 138, 146, 147,
	148, 149, 150, 151, 152, 153, 154, 162, 163, 164, 165, 166, 167, 168, 169, 170, 178,
	179, 180, 181, 182, 183, 184, 185, 186, 194, 195, 196, 197, 198, 199, 200, 201, 202,
	210, 211, 212, 213, 214, 215, 216, 217, 218, 225, 226, 227, 228, 229, 230, 231, 232,
	233, 234, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250
]
jpeg_ac_chroma_counts := [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 119]
jpeg_ac_chroma_values := [
	0, 1, 2, 3, 17, 4, 5, 33, 49, 6, 18, 65, 81, 7, 97, 113, 19, 34, 50, 129, 8, 20, 66,
	145, 161, 177, 193, 9, 35, 51, 82, 240, 21, 98, 114, 209, 10, 22, 36, 52, 225, 37,
	241, 23, 24, 25, 26, 38, 39, 40, 41, 42, 53, 54, 55, 56, 57, 58, 67, 68, 69, 70, 71,
	72, 73, 74, 83, 84, 85, 86, 87, 88, 89, 90, 99, 100, 101, 102, 103, 104, 105, 106,
	115, 116, 117, 118, 119, 120, 121, 122, 130, 131, 132, 133, 134, 135, 136, 137, 138,
	146, 147, 148, 149, 150, 151, 152, 153, 154, 162, 163, 164, 165, 166, 167, 168, 169,
	170, 178, 179, 180, 181, 182, 183, 184, 185, 186, 194, 195, 196, 197, 198, 199, 200,
	201, 202, 210, 211, 212, 213, 214, 215, 216, 217, 218, 226, 227, 228, 229, 230, 231,
	232, 233, 234, 242, 243, 244, 245, 246, 247, 248, 249, 250
]

// Code and length per symbol for an encoder.
type JpegCodes:
	code: List[Int]
	size: List[Int]

fn jpeg_codes(counts: List[Int], values: List[Int]) JpegCodes:
	var code = jpeg_zeros(256)
	var size = jpeg_zeros(256)
	var next = 0
	var index = 0

	for length in 1..17:
		for _slot in 0..counts[length - 1]:
			code[values[index]] = next
			size[values[index]] = length
			next += 1
			index += 1

		next *= 2

	return JpegCodes(code, size)

type JpegWriter:
	out: BytesBuilder
	acc: Int
	count: Int

fn var JpegWriter.put(code: Int, size: Int) Unit:
	self.acc = bit_or(shift_left(self.acc, size), code)
	self.count += size

	while self.count >= 8:
		b := bit_and(shift_right_unsigned(self.acc, self.count - 8), 255)
		self.out.append(byte(b))
		if b == 255: self.out.append(byte(0))
		self.count -= 8

	self.acc = bit_and(self.acc, shift_left(1, self.count) - 1)

// Pads the partial byte with 1-bits, as the format requires before a marker.
fn var JpegWriter.align() Unit:
	if self.count > 0: self.put(shift_left(1, 8 - self.count) - 1, 8 - self.count)

fn bit_length(value: Int) Int:
	var v = if value < 0: 0 - value else: value
	var n = 0

	while v > 0:
		n += 1
		v /= 2

	return n

// Forward DCT and quantization of the 8x8 block at (x0, y0); returns 64 levels in
// jpeg_zigzag order.
fn jpeg_forward(
	plane: List[Int],
	stride: Int,
	x0: Int,
	y0: Int,
	quant: List[Int],
) List[Int]:
	var tmp = jpeg_zeros(64)

	for y in 0..8:
		for u in 0..8:
			var sum = 0
			for x in 0..8:
				sum += (
					jpeg_dct_matrix[x * 8 + u]
					* (plane[(y0 + y) * stride + x0 + x] - 128)
				)
			tmp[y * 8 + u] = sum

	var levels = jpeg_zeros(64)

	for zi in 0..64:
		at := jpeg_zigzag[zi]
		v := at / 8
		u := at % 8
		var sum = 0
		for y in 0..8:
			sum += jpeg_dct_matrix[y * 8 + v] * tmp[y * 8 + u]

		q := quant[zi]
		half := q * 8388608
		scale := q * 16777216
		levels[zi] = if sum >= 0: (sum + half) / scale else: 0 - ((half - sum) / scale)

	return levels

fn jpeg_emit(
	var w: JpegWriter,
	levels: List[Int],
	previous: Int,
	dc: JpegCodes,
	ac: JpegCodes,
) Unit:
	diff := levels[0] - previous
	size := bit_length(diff)
	w.put(dc.code[size], dc.size[size])
	if size > 0: w.put(if diff >= 0: diff else: diff + shift_left(1, size) - 1, size)

	var run = 0

	for zi in 1..64:
		v := levels[zi]

		if v == 0:
			run += 1
		else:
			while run > 15:
				w.put(ac.code[240], ac.size[240])
				run -= 16

			n := bit_length(v)
			symbol := run * 16 + n
			w.put(ac.code[symbol], ac.size[symbol])
			w.put(if v >= 0: v else: v + shift_left(1, n) - 1, n)
			run = 0

	if run > 0: w.put(ac.code[0], ac.size[0])

fn put16_be(var out: BytesBuilder, value: Int) Unit:
	out.append(byte(bit_and(shift_right_unsigned(value, 8), 255)))
	out.append(byte(bit_and(value, 255)))

fn jpeg_marker(var out: BytesBuilder, marker: Int, body: Bytes) Unit:
	out.append(byte(255))
	out.append(byte(marker))
	put16_be(var out, body.length() + 2)
	out.append_bytes(body)

fn jpeg_dht(var out: BytesBuilder, class_id: Int, counts: List[Int], values: List[Int]) Unit:
	var body = BytesBuilder()
	body.append(byte(class_id))
	for c in counts:
		body.append(byte(c))
	for v in values:
		body.append(byte(v))
	jpeg_marker(var out, 196, body.build())

fn jpeg_scaled(base: List[Int], quality: Int) List[Int]:
	scale := if quality < 50: 5000 / quality else: 200 - quality * 2
	var table = List[Int]()
	for zi in 0..64:
		table.append(jpeg_clamp(max_of((base[zi] * scale + 50) / 100, 1), 255))
	return table

// Encodes baseline JPEG of `pixels` (`channels` 1 or 3; alpha fails with `EINVAL`);
// `quarter` subsamples chroma 4:2:0, `restart_interval` is MCUs between restart markers
// or 0.
export fn jpeg_encode(
	width: Int,
	height: Int,
	channels: Int,
	pixels: List[UInt8],
	quality: Int,
	quarter: Bool,
	restart_interval: Int,
) Bytes!:
	if channels % 2 == 0:
		return error(
			Error(
				"image: JPEG cannot store alpha; convert to Rgb or Gray first",
				kind: "EINVAL",
			)
		)
	if quality < 1 or quality > 100:
		return error(Error("image: JPEG quality must be 1 to 100", kind: "EINVAL"))
	if restart_interval < 0 or restart_interval > 65535:
		return error(
			Error(
				"image: JPEG restart interval must be 0 to 65535",
				kind: "EINVAL",
			)
		)
	if width > 65535 or height > 65535:
		return error(too_big("JPEG dimensions are limited to 65535"))

	color := channels == 3
	sub := color and quarter
	unit_size := if sub: 16 else: 8
	mcus_x := (width + unit_size - 1) / unit_size
	mcus_y := (height + unit_size - 1) / unit_size
	pw := mcus_x * unit_size
	ph := mcus_y * unit_size

	// Full-resolution planes, edge-replicated to whole MCUs.
	var luma = jpeg_zeros(pw * ph)
	var cb = jpeg_zeros(if color: pw * ph else: 0)
	var cr = jpeg_zeros(if color: pw * ph else: 0)
	n := channels

	for y in 0..ph:
		sy := min_of(y, height - 1)

		for x in 0..pw:
			at := (sy * width + min_of(x, width - 1)) * n

			if color:
				r := pixels[at].to_int()
				g := pixels[at + 1].to_int()
				b := pixels[at + 2].to_int()
				luma[y * pw + x] = shift_right(
					19595 * r + 38470 * g + 7471 * b + 32768,
					16,
				)
				cb[y * pw + x] = shift_right(
					0 - 11059 * r - 21709 * g + 32768 * b + 8421376,
					16,
				)
				cr[y * pw + x] = shift_right(
					32768 * r - 27439 * g - 5329 * b + 8421376,
					16,
				)
			else:
				luma[y * pw + x] = pixels[at].to_int()

	var cw = pw

	if sub:
		cw = pw / 2

		var small_cb = jpeg_zeros(cw * (ph / 2))
		var small_cr = jpeg_zeros(cw * (ph / 2))

		for y in 0..ph / 2:
			for x in 0..cw:
				i := 2 * y * pw + 2 * x
				small_cb[y * cw + x] = (
					(
						cb[i]
						+ cb[i + 1]
						+ cb[i + pw]
						+ cb[i + pw + 1]
						+ 2
					)
					/ 4
				)
				small_cr[y * cw + x] = (
					(
						cr[i]
						+ cr[i + 1]
						+ cr[i + pw]
						+ cr[i + pw + 1]
						+ 2
					)
					/ 4
				)

		cb = small_cb
		cr = small_cr

	q_luma := jpeg_scaled(jpeg_base_luma, quality)
	q_chroma := jpeg_scaled(jpeg_base_chroma, quality)
	var out = BytesBuilder()
	out.append(byte(255))
	out.append(byte(216))
	jpeg_marker(var out, 224, Bytes([74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]))

	var table_bytes = BytesBuilder()
	table_bytes.append(byte(0))
	for q in q_luma:
		table_bytes.append(byte(q))
	jpeg_marker(var out, 219, table_bytes.build())

	if color:
		var chroma_table = BytesBuilder()
		chroma_table.append(byte(1))
		for q in q_chroma:
			chroma_table.append(byte(q))
		jpeg_marker(var out, 219, chroma_table.build())

	var frame = BytesBuilder()
	frame.append(byte(8))
	put16_be(var frame, height)
	put16_be(var frame, width)
	frame.append(byte(if color: 3 else: 1))
	frame.append(byte(1))
	frame.append(byte(if sub: 34 else: 17))
	frame.append(byte(0))

	if color:
		frame.append(byte(2))
		frame.append(byte(17))
		frame.append(byte(1))
		frame.append(byte(3))
		frame.append(byte(17))
		frame.append(byte(1))

	jpeg_marker(var out, 192, frame.build())
	jpeg_dht(var out, 0, jpeg_dc_luma_counts, jpeg_dc_values)
	jpeg_dht(var out, 16, jpeg_ac_luma_counts, jpeg_ac_luma_values)

	if color:
		jpeg_dht(var out, 1, jpeg_dc_chroma_counts, jpeg_dc_values)
		jpeg_dht(var out, 17, jpeg_ac_chroma_counts, jpeg_ac_chroma_values)

	if restart_interval > 0:
		var dri = BytesBuilder()
		put16_be(var dri, restart_interval)
		jpeg_marker(var out, 221, dri.build())

	var scan = BytesBuilder()
	scan.append(byte(if color: 3 else: 1))
	scan.append(byte(1))
	scan.append(byte(0))

	if color:
		scan.append(byte(2))
		scan.append(byte(17))
		scan.append(byte(3))
		scan.append(byte(17))

	scan.append(byte(0))
	scan.append(byte(63))
	scan.append(byte(0))
	jpeg_marker(var out, 218, scan.build())

	dc_luma := jpeg_codes(jpeg_dc_luma_counts, jpeg_dc_values)
	ac_luma := jpeg_codes(jpeg_ac_luma_counts, jpeg_ac_luma_values)
	dc_chroma := jpeg_codes(jpeg_dc_chroma_counts, jpeg_dc_values)
	ac_chroma := jpeg_codes(jpeg_ac_chroma_counts, jpeg_ac_chroma_values)
	var w = JpegWriter(out, 0, 0)
	var p_y = 0
	var p_cb = 0
	var p_cr = 0
	var mcu = 0

	for my in 0..mcus_y:
		for mx in 0..mcus_x:
			if (restart_interval > 0 and mcu > 0 and mcu % restart_interval == 0):
				w.align()
				w.out.append(byte(255))
				w.out.append(byte(208 + (mcu / restart_interval - 1) % 8))
				p_y = 0
				p_cb = 0
				p_cr = 0

			blocks_y := if sub: 2 else: 1

			for by in 0..blocks_y:
				for bx in 0..blocks_y:
					levels := jpeg_forward(
						luma,
						pw,
						mx * unit_size + bx * 8,
						my * unit_size + by * 8,
						q_luma,
					)
					jpeg_emit(var w, levels, p_y, dc_luma, ac_luma)
					p_y = levels[0]

			if color:
				x0 := mx * 8
				y0 := my * 8
				lb := jpeg_forward(cb, cw, x0, y0, q_chroma)
				jpeg_emit(var w, lb, p_cb, dc_chroma, ac_chroma)
				p_cb = lb[0]

				lr := jpeg_forward(cr, cw, x0, y0, q_chroma)
				jpeg_emit(var w, lr, p_cr, dc_chroma, ac_chroma)
				p_cr = lr[0]

			mcu += 1

	w.align()
	w.out.append(byte(255))
	w.out.append(byte(217))
	return ok(w.out.build())
