import (
	Bytes from "@std/bytes.ms",
	Raster,
	bad,
	byte,
	max_of,
	min_of,
	pixel_count,
	unsupported,
	zeroed from "@std/image/codec.ms",
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

// ---- JPEG ----

type JpegHuffman:
	present: Bool
	mincode: List[Int]
	maxcode: List[Int]
	valptr: List[Int]
	values: List[Int]

type JpegComponent:
	id: Int
	h: Int
	v: Int
	tq: Int
	// Block grid padded to whole MCUs.
	blocks_wide: Int
	blocks_high: Int
	// 64 coefficients per block, natural order, quantized until the final pass.
	coef: List[Int]
	quant: List[Int]
	pred: Int

type JpegBits:
	pos: Int
	acc: Int
	count: Int
	failed: Bool
	eobrun: Int

fn var JpegBits.bit(data: Bytes) Int:
	if self.count == 0:
		if self.pos >= data.length():
			self.failed = true
			return 0

		var b = data.get(self.pos).to_int()

		if b == 255:
			next := if self.pos + 1 < data.length(): data.get(
				self.pos + 1
			).to_int() else: 217

			if next != 0:
				// A marker ends the entropy-coded segment; reading into it is
				// corruption.
				self.failed = true
				return 0

			self.pos += 2
		else:
			self.pos += 1

		self.acc = b
		self.count = 8

	self.count -= 1
	return bit_and(shift_right_unsigned(self.acc, self.count), 1)

fn var JpegBits.receive(data: Bytes, n: Int) Int:
	var v = 0
	for i in 0..n:
		v = v * 2 + self.bit(data)
	return v

// Decodes one symbol, or -1 after setting `failed`.
fn var JpegBits.symbol(data: Bytes, table: JpegHuffman) Int:
	var code = 0

	for length in 1..17:
		code = code * 2 + self.bit(data)
		if self.failed: return -1
		if (
			table.maxcode[length] >= 0
			and code <= table.maxcode[length]
			and code >= table.mincode[length]
		):
			return table.values[table.valptr[length] + code - table.mincode[length]]

	self.failed = true
	return -1

fn jpeg_extend(value: Int, size: Int) Int:
	if size == 0: return 0
	if value < shift_left(1, size - 1): return value - shift_left(1, size) + 1

	return value

fn be16(data: Bytes, at: Int) Int:
	return data.get(at).to_int() * 256 + data.get(at + 1).to_int()

fn build_huffman(counts: List[Int], values: List[Int]) JpegHuffman!:
	var mincode = [0].repeated(17)
	var maxcode = [-1].repeated(17)
	var valptr = [0].repeated(17)
	var code = 0
	var zi = 0

	for length in 1..17:
		valptr[length] = zi
		mincode[length] = code
		code += counts[length - 1]
		zi += counts[length - 1]
		if counts[length - 1] > 0: maxcode[length] = code - 1
		if code > shift_left(1, length): return error(
			bad("oversubscribed Huffman table")
		)

		code *= 2

	return ok(JpegHuffman(true, mincode, maxcode, valptr, values))

fn empty_huffman() JpegHuffman:
	return JpegHuffman(false, List[Int](), List[Int](), List[Int](), List[Int]())

// Coded blocks in the scan.
type JpegScan:
	members: List[Int]
	ss: Int
	se: Int
	ah: Int
	al: Int
	progressive: Bool

fn jpeg_block(
	data: Bytes,
	var bits: JpegBits,
	var comp: JpegComponent,
	base: Int,
	dc: JpegHuffman,
	ac: JpegHuffman,
	scan: JpegScan,
) Unit:
	if not scan.progressive:
		t := bits.symbol(data, dc)

		if t < 0 or t > 15:
			bits.failed = true
			return

		comp.pred += jpeg_extend(bits.receive(data, t), t)
		comp.coef[base] = comp.pred

		var zi = 1

		while zi < 64:
			rs := bits.symbol(data, ac)
			if rs < 0: return

			r := rs / 16
			size := rs % 16

			if size == 0:
				if r != 15: break

				zi += 16
			else:
				zi += r

				if zi > 63:
					bits.failed = true
					return

				comp.coef[base + jpeg_zigzag[zi]] = jpeg_extend(
					bits.receive(data, size),
					size,
				)
				zi += 1

		return

	if scan.ss == 0:
		if scan.ah == 0:
			t := bits.symbol(data, dc)

			if t < 0 or t > 15:
				bits.failed = true
				return

			comp.pred += jpeg_extend(bits.receive(data, t), t)
			comp.coef[base] = comp.pred * shift_left(1, scan.al)
		else:
			if bits.bit(data) == 1: comp.coef[base] = bit_or(
				comp.coef[base],
				shift_left(1, scan.al),
			)

		return

	if scan.ah == 0:
		if bits.eobrun > 0:
			bits.eobrun -= 1
			return

		var zi = scan.ss

		while zi <= scan.se:
			rs := bits.symbol(data, ac)
			if rs < 0: return

			r := rs / 16
			size := rs % 16

			if size != 0:
				zi += r

				if zi > 63:
					bits.failed = true
					return

				comp.coef[base + jpeg_zigzag[zi]] = (
					jpeg_extend(bits.receive(data, size), size)
					* shift_left(1, scan.al)
				)
				zi += 1
			else if r == 15:
				zi += 16
			else:
				bits.eobrun = shift_left(1, r)
				if r > 0: bits.eobrun += bits.receive(data, r)
				bits.eobrun -= 1
				break

		return

	// AC refinement.
	p1 := shift_left(1, scan.al)
	m1 := 0 - p1
	var zi = scan.ss

	if bits.eobrun == 0:
		while zi <= scan.se:
			rs := bits.symbol(data, ac)
			if rs < 0: return

			var r = rs / 16
			var value = 0

			if rs % 16 != 0:
				value = if bits.bit(data) == 1: p1 else: m1
			else if r != 15:
				bits.eobrun = shift_left(1, r)
				if r > 0: bits.eobrun += bits.receive(data, r)
				break

			while zi <= scan.se:
				at := base + jpeg_zigzag[zi]

				if comp.coef[at] != 0:
					if bits.bit(data) == 1 and bit_and(comp.coef[at], p1) == 0:
						comp.coef[at] += if comp.coef[at] >= 0: p1 else: m1
				else:
					r -= 1
					if r < 0: break

				zi += 1

			if value != 0:
				if zi > 63:
					bits.failed = true
					return

				comp.coef[base + jpeg_zigzag[zi]] = value

			zi += 1
			if bits.failed: return

	if bits.eobrun > 0:
		while zi <= scan.se:
			at := base + jpeg_zigzag[zi]
			if comp.coef[at] != 0:
				if bits.bit(data) == 1 and bit_and(comp.coef[at], p1) == 0:
					comp.coef[at] += if comp.coef[at] >= 0: p1 else: m1
			zi += 1

		bits.eobrun -= 1

// Dequantizes and inverse-transforms every block of `comp` into a padded sample plane.
fn jpeg_plane(comp: JpegComponent) List[UInt8]:
	stride := comp.blocks_wide * 8
	var plane = zeroed(stride * comp.blocks_high * 8)
	var tmp = [0].repeated(64)

	for by in 0..comp.blocks_high:
		for bx in 0..comp.blocks_wide:
			base := (by * comp.blocks_wide + bx) * 64

			// Rows: tmp[y][x] = sum_u M[x][u] * F[y][u], kept at scale 64.
			for y in 0..8:
				for x in 0..8:
					var sum = 0

					for u in 0..8:
						f := comp.coef[base + y * 8 + u]
						if f != 0: sum += (
							jpeg_dct_matrix[x * 8 + u]
							* f
							* comp.quant[y * 8 + u]
						)

					tmp[y * 8 + x] = shift_right(sum + 32, 6)

			for x in 0..8:
				for y in 0..8:
					var sum = 0
					for v in 0..8:
						sum += jpeg_dct_matrix[y * 8 + v] * tmp[v * 8 + x]
					plane[(by * 8 + y) * stride + bx * 8 + x] = byte(
						shift_right(sum + 131072, 18) + 128
					)

	return plane

// Decodes baseline or progressive JPEG into a raster; `EBADMSG`, `ENOTSUP` or
// `EOVERFLOW` on failure.
export fn decode_jpeg(data: Bytes, max_pixels: Int?) Raster!:
	n := data.length()
	if n < 4 or data.get(0).to_int() != 255 or data.get(1).to_int() != 216:
		return error(bad("not a JPEG"))

	var quants = [List[Int](), List[Int](), List[Int](), List[Int]()]
	var dc_tables = [empty_huffman(), empty_huffman(), empty_huffman(), empty_huffman()]
	var ac_tables = [empty_huffman(), empty_huffman(), empty_huffman(), empty_huffman()]
	var comps = List[JpegComponent]()
	var width = 0
	var height = 0
	var progressive = false
	var have_frame = false
	var have_scan = false
	var restart = 0
	var adobe = -1
	var jfif = false
	var hmax = 1
	var vmax = 1
	var mcus_x = 0
	var mcus_y = 0
	var at = 2
	var done = false

	while not done:
		// Find the next marker, skipping fill bytes.
		if at >= n: return error(bad("truncated JPEG: missing EOI"))
		if data.get(at).to_int() != 255: return error(
			bad("expected a JPEG marker at byte {at}")
		)

		while at < n and data.get(at).to_int() == 255:
			at += 1
		if at >= n: return error(bad("truncated JPEG marker"))

		marker := data.get(at).to_int()
		at += 1

		if marker == 217:
			done = true
		else if marker == 216:
			return error(bad("nested JPEG start marker"))
		else if marker == 1 or (marker >= 208 and marker <= 215) or marker == 0:
			unit
		else:
			if at + 2 > n: return error(bad("truncated JPEG segment"))

			length := be16(data, at)
			if length < 2 or at + length > n: return error(
				bad("truncated JPEG segment")
			)

			body := at + 2
			end := at + length

			if marker == 219:
				var p = body

				while p < end:
					precision := data.get(p).to_int() / 16
					id := data.get(p).to_int() % 16
					if id > 3 or precision > 1: return error(
						bad("bad JPEG quantization table")
					)

					size := if precision == 1: 128 else: 64
					if p + 1 + size > end: return error(
						bad("truncated JPEG quantization table")
					)

					var table = [0].repeated(64)

					for zi in 0..64:
						var v = data.get(p + 1 + zi).to_int()
						if precision == 1: v = be16(data, p + 1 + zi * 2)
						if v == 0: return error(bad("zero JPEG quantizer"))

						table[jpeg_zigzag[zi]] = v

					quants[id] = table
					p += 1 + size

				at = end
			else if marker == 196:
				var p = body

				while p < end:
					if p + 17 > end: return error(bad("truncated JPEG Huffman table"))

					table_class := data.get(p).to_int() / 16
					id := data.get(p).to_int() % 16
					if table_class > 1 or id > 3: return error(
						bad("bad JPEG Huffman table")
					)

					var counts = List[Int]()
					var total = 0

					for zi in 0..16:
						counts.append(data.get(p + 1 + zi).to_int())
						total += counts[zi]

					if total > 256 or p + 17 + total > end: return error(
						bad("truncated JPEG Huffman table")
					)

					var values = List[Int]()
					for zi in 0..total:
						values.append(data.get(p + 17 + zi).to_int())

					table := build_huffman(counts, values)?

					if table_class == 0:
						dc_tables[id] = table
					else:
						ac_tables[id] = table

					p += 17 + total

				at = end
			else if marker == 192 or marker == 193 or marker == 194:
				if have_frame: return error(bad("multiple JPEG frames"))
				if length < 8: return error(bad("truncated JPEG frame header"))
				if data.get(body).to_int() != 8: return error(
					unsupported(
						"JPEG sample precision {data.get(body)}"
					)
				)

				height = be16(data, body + 1)
				width = be16(data, body + 3)

				count := data.get(body + 5).to_int()
				if height == 0: return error(
					unsupported("JPEG with deferred height (DNL)")
				)
				if width == 0 or (count != 1 and count != 3 and count != 4):
					return error(
						unsupported(
							"JPEG with {count} components or zero width"
						)
					)
				if length != 8 + count * 3: return error(
					bad("bad JPEG frame header length")
				)

				_total := pixel_count(width, height, max_pixels)?
				progressive = marker == 194

				for i in 0..count:
					q := body + 6 + i * 3
					h := data.get(q + 1).to_int() / 16
					v := data.get(q + 1).to_int() % 16
					tq := data.get(q + 2).to_int()
					if h < 1 or h > 4 or v < 1 or v > 4 or tq > 3: return error(
						bad("bad JPEG component")
					)

					comps.append(
						JpegComponent(
							data.get(q).to_int(),
							h,
							v,
							tq,
							0,
							0,
							List[Int](),
							List[Int](),
							0,
						)
					)
					hmax = max_of(hmax, h)
					vmax = max_of(vmax, v)

				mcus_x = (width + hmax * 8 - 1) / (hmax * 8)
				mcus_y = (height + vmax * 8 - 1) / (vmax * 8)

				for i in 0..count:
					comps[i].blocks_wide = mcus_x * comps[i].h
					comps[i].blocks_high = mcus_y * comps[i].v

				have_frame = true
				at = end
			else if marker == 221:
				if length != 4: return error(bad("bad JPEG restart interval"))

				restart = be16(data, body)
				at = end
			else if marker == 238:
				if (
					length >= 14
					and data.get(body).to_int() == 65
					and data.get(body + 1).to_int() == 100
					and data.get(body + 2).to_int() == 111
				):
					adobe = data.get(body + 11).to_int()
				at = end
			else if marker == 224:
				jfif = true
				at = end
			else if (
				marker == 195
				or (
					marker >= 197
					and marker <= 207
					and marker != 196
					and marker != 200
					and marker != 204
				)
			):
				return error(
					unsupported(
						"JPEG process (marker {marker}); arithmetic and lossless coding are not supported"
					)
				)
			else if marker == 218:
				if not have_frame: return error(bad("JPEG scan before frame header"))

				ns := data.get(body).to_int()
				if ns < 1 or ns > 4 or length != 6 + ns * 2: return error(
					bad("bad JPEG scan header")
				)

				var members = List[Int]()
				var dc_ids = List[Int]()
				var ac_ids = List[Int]()

				for i in 0..ns:
					q := body + 1 + i * 2
					var found = -1
					for c in 0..comps.length():
						if comps[c].id == data.get(q).to_int(): found = c
					if found < 0: return error(
						bad(
							"JPEG scan names an unknown component"
						)
					)
					if members.contains(found): return error(
						bad("JPEG scan repeats a component")
					)

					members.append(found)
					dc_ids.append(data.get(q + 1).to_int() / 16)
					ac_ids.append(data.get(q + 1).to_int() % 16)
					if dc_ids[i] > 3 or ac_ids[i] > 3: return error(
						bad("bad JPEG table selector")
					)

				tail := body + 1 + ns * 2
				var ss = data.get(tail).to_int()
				var se = data.get(tail + 1).to_int()
				ah := data.get(tail + 2).to_int() / 16
				al := data.get(tail + 2).to_int() % 16

				if not progressive:
					ss = 0
					se = 63
				else:
					if ss > se or se > 63 or ah > 13 or al > 13: return error(
						bad("bad JPEG spectral selection")
					)
					if ss == 0 and se != 0: return error(
						bad("progressive DC scan with AC range")
					)
					if ss > 0 and ns != 1: return error(
						bad(
							"progressive AC scan with several components"
						)
					)

				scan := JpegScan(members.clone(), ss, se, ah, al, progressive)

				// Blocks per component this scan codes, and the allocation budget
				// check.
				var coded = 0

				if ns == 1:
					c := members[0]
					cw := (width * comps[c].h + hmax - 1) / hmax
					ch := (height * comps[c].v + vmax - 1) / vmax
					coded = ((cw + 7) / 8) * ((ch + 7) / 8)
				else:
					for c in members:
						coded += mcus_x * mcus_y * comps[c].h * comps[c].v

				if coded > (n - end) * 8 + 64: return error(
					bad("JPEG scan is longer than its data")
				)

				for m in 0..members.length():
					c := members[m]

					if comps[c].coef.is_empty():
						if progressive and (ss != 0 or ah != 0):
							return error(bad("progressive scan precedes its DC scan"))
						if quants[comps[c].tq].is_empty(): return error(
							bad(
								"JPEG uses a missing quantization table"
							)
						)

						comps[c].quant = quants[comps[c].tq].clone()
						comps[c].coef = jpeg_zeros(
							comps[c].blocks_wide * comps[
								c
							].blocks_high * 64
						)

					needs_dc := not progressive or (ss == 0 and ah == 0)
					needs_ac := not progressive or ss > 0
					if needs_dc and not dc_tables[dc_ids[m]].present:
						return error(bad("JPEG scan uses a missing DC table"))
					if needs_ac and not ac_tables[ac_ids[m]].present:
						return error(bad("JPEG scan uses a missing AC table"))

					comps[c].pred = 0

				var bits = JpegBits(end, 0, 0, false, 0)
				units := if ns == 1: coded else: mcus_x * mcus_y
				var across = mcus_x
				if ns == 1:
					across = ((width * comps[members[0]].h + hmax - 1) / hmax + 7) / 8

				var step_index = 0

				while step_index < units:
					if restart > 0 and step_index > 0 and step_index % restart == 0:
						// Drop the partial byte; the next two bytes must be RSTn.
						bits.count = 0
						bits.acc = 0
						if bits.pos + 1 >= n or data.get(bits.pos).to_int() != 255:
							return error(bad("missing JPEG restart marker"))

						rst := data.get(bits.pos + 1).to_int()
						if rst < 208 or rst > 215: return error(
							bad(
								"missing JPEG restart marker"
							)
						)

						bits.pos += 2
						bits.eobrun = 0
						for c in members:
							comps[c].pred = 0

					ux := step_index % across
					uy := step_index / across

					for m in 0..members.length():
						c := members[m]

						if ns == 1:
							base := (uy * comps[c].blocks_wide + ux) * 64
							jpeg_block(
								data,
								var bits,
								var comps[c],
								base,
								dc_tables[dc_ids[m]],
								ac_tables[ac_ids[m]],
								scan,
							)
						else:
							for v in 0..comps[c].v:
								for h in 0..comps[c].h:
									base := (
										(
											(
												uy * comps[
													c
												].v
												+ v
											) * comps[c].blocks_wide
											+ ux * comps[
												c
											].h
											+ h
										)
										* 64
									)
									jpeg_block(
										data,
										var bits,
										var comps[
											c
										],
										base,
										dc_tables[
											dc_ids[
												m
											]
										],
										ac_tables[
											ac_ids[
												m
											]
										],
										scan,
									)

					if bits.failed: return error(bad("corrupt or truncated JPEG data"))

					step_index += 1

				have_scan = true

				// Resume at the marker that ends the entropy data.
				at = scan_end(data, bits.pos)
			else:
				at = end

	if not have_frame or not have_scan: return error(bad("JPEG has no image data"))

	// Planes, then upsample + color convert.
	var planes = List[List[UInt8]]()
	for c in comps:
		planes.append(jpeg_plane(c))

	zi := comps.length()
	var spans = List[List[Int]]()
	for c in comps:
		spans.append(
			[
				(width * c.h + hmax - 1) / hmax,
				(height * c.v + vmax - 1) / vmax,
			]
		)

	m := if zi == 1: 1 else: 3
	var pixels = zeroed(width * height * m)
	ycc := (
		zi == 3
		and adobe != 0
		and not (
			comps[0].id == 82
			and comps[1].id == 71
			and comps[2].id == 66
			and not jfif
		)
	)

	for y in 0..height:
		for x in 0..width:
			var s = [0, 0, 0, 0]

			for c in 0..zi:
				stride := comps[c].blocks_wide * 8
				s[c] = jpeg_sample(
					planes[c],
					stride,
					spans[c],
					y,
					x,
					hmax / comps[c].h,
					vmax / comps[c].v,
					hmax % comps[c].h == 0 and vmax % comps[
						c
					].v == 0,
				)

			out := (y * width + x) * m

			if zi == 1:
				pixels[out] = byte(s[0])
			else if zi == 3 and not ycc:
				pixels[out] = byte(s[0])
				pixels[out + 1] = byte(s[1])
				pixels[out + 2] = byte(s[2])
			else if zi == 3:
				rgb := ycc_to_rgb(s[0], s[1], s[2])
				pixels[out] = byte(rgb[0])
				pixels[out + 1] = byte(rgb[1])
				pixels[out + 2] = byte(rgb[2])
			else:
				// Four components: Adobe CMYK/YCCK store inverted ink, so a stored
				// value acts as its own transmittance.
				var t0 = s[0]
				var t1 = s[1]
				var t2 = s[2]
				var tk = s[3]

				if adobe == 2:
					rgb := ycc_to_rgb(s[0], s[1], s[2])
					t0 = 255 - rgb[0]
					t1 = 255 - rgb[1]
					t2 = 255 - rgb[2]

				if adobe < 0:
					t0 = 255 - t0
					t1 = 255 - t1
					t2 = 255 - t2
					tk = 255 - tk

				pixels[out] = byte(t0 * tk / 255)
				pixels[out + 1] = byte(t1 * tk / 255)
				pixels[out + 2] = byte(t2 * tk / 255)

	return ok(Raster(width, height, m, pixels))

// First offset at or after `from` that starts a marker other than a stuffed zero, fill
// or restart.
fn scan_end(data: Bytes, from: Int) Int:
	var at = from

	while at + 1 < data.length():
		b := data.get(at + 1).to_int()
		if (
			data.get(at).to_int() == 255
			and b != 0
			and b != 255
			and (b < 208 or b > 215)
		): return at

		at += 1

	return data.length()

// Reads component sample (x, y) of the full-resolution grid. A 2:1 ratio uses libjpeg's
// triangle filter ("fancy" upsampling) so output matches libjpeg; other ratios
// replicate the nearest sample.
fn jpeg_sample(
	plane: List[UInt8],
	stride: Int,
	span: List[Int],
	y: Int,
	x: Int,
	hr: Int,
	vr: Int,
	exact: Bool,
) Int:
	if not exact or (hr == 1 and vr == 1) or hr > 2 or vr > 2:
		return plane[(y / max_of(vr, 1)) * stride + x / max_of(hr, 1)].to_int()

	last_x := span[0] - 1
	last_y := span[1] - 1
	px := min_of(x / hr, last_x)
	py := min_of(y / vr, last_y)

	if vr == 1:
		here := plane[py * stride + px].to_int()
		near := plane[
			py * stride + jpeg_clamp(
				if x % 2 == 0: px - 1 else: px + 1,
				last_x,
			)
		].to_int()
		return (3 * here + near + (if x % 2 == 0: 1 else: 2)) / 4

	ny := jpeg_clamp(if y % 2 == 0: py - 1 else: py + 1, last_y)

	if hr == 1:
		here := plane[py * stride + px].to_int()
		near := plane[ny * stride + px].to_int()
		return (3 * here + near + (if y % 2 == 0: 1 else: 2)) / 4

	nx := jpeg_clamp(if x % 2 == 0: px - 1 else: px + 1, last_x)
	here := 3 * plane[py * stride + px].to_int() + plane[ny * stride + px].to_int()
	near := 3 * plane[py * stride + nx].to_int() + plane[ny * stride + nx].to_int()
	return (3 * here + near + (if x % 2 == 0: 8 else: 7)) / 16

fn ycc_to_rgb(y: Int, cb: Int, cr: Int) List[Int]:
	u := cb - 128
	v := cr - 128
	return [
		y + shift_right(91881 * v + 32768, 16),
		y - shift_right(22554 * u + 46802 * v + 32768, 16),
		y + shift_right(116130 * u + 32768, 16),
	]
