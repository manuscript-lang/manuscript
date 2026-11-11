import (
	hex_decode from "@std/data/encoding.ms",
	Chroma,
	ColorMode,
	ImageFormat,
	JpegOptions,
	Rgba,
	decode_image,
	encode_image,
	encode_jpeg,
	new_image from "@std/image/image.ms",
	expect_equal, fail from "@std/test/test.ms",

	jpeg_vectors from "./image-jpeg-vectors.ms",
	vectors from "./image-png-vectors.ms",
)

test "ppm round trip":
	var img = new_image(3, 2, ColorMode.Rgb).get()
	img.set_pixel(1, 1, Rgba(10, 20, 30))

	data := encode_image(img, ImageFormat.Ppm).get()
	back := decode_image(data).get()
	try expect_equal(back.width, 3)
	try expect_equal(back.pixels.length(), 18)
	try expect_equal(back.pixel(1, 1).get().green, 20)

test "bmp round trip":
	var img = new_image(5, 3, ColorMode.Rgba).get()
	img.set_pixel(4, 2, Rgba(1, 2, 3, 200))

	back := decode_image(encode_image(img, ImageFormat.Bmp).get()).get()
	try expect_equal(back.pixel(4, 2).get().alpha, 200)
	try expect_equal(back.pixel(0, 0).get().alpha, 255)

fn expect_pixel(hex: String, red: Int, green: Int, blue: Int) Unit!:
	px := decode_image(hex_decode(hex, none).get()).get().pixel(0, 0).get()
	return expect_equal([px.red, px.green, px.blue], [red, green, blue])

test "ppm two-byte samples use both bytes and scale by maxval":
	// P6 1x1 with maxval 256 and 1023 white, and maxval 65535 interior levels.
	try expect_pixel("50360a3120310a3235360a010001000100", 255, 255, 255)
	try expect_pixel("50360a3120310a313032330a03ff03ff03ff", 255, 255, 255)
	try expect_pixel("50360a3120310a36353533350a7fff00008000", 127, 0, 128)

	// P5 with maxval 65535: gray fills all channels.
	try expect_pixel("50350a3120310a36353533350a ffff".replace(" ", ""), 255, 255, 255)
	try expect_pixel("50350a3120310a3235350a80", 128, 128, 128)

test "bmp alpha survives with explicit masks":
	var img = new_image(3, 2, ColorMode.Rgba).get()
	img.set_pixel(0, 0, Rgba(10, 20, 30, 0))
	img.set_pixel(1, 0, Rgba(10, 20, 30, 1))
	img.set_pixel(2, 0, Rgba(10, 20, 30, 128))

	data := encode_image(img, ImageFormat.Bmp).get()

	// BITMAPV4HEADER, BI_BITFIELDS, pixels at 122.
	try expect_equal(data.get(14).to_int(), 108)
	try expect_equal(data.get(30).to_int(), 3)
	try expect_equal(data.get(10).to_int(), 122)

	back := decode_image(data).get()
	try expect_equal(back.pixel(0, 0).get().alpha, 0)
	try expect_equal(back.pixel(1, 0).get().alpha, 1)
	try expect_equal(back.pixel(2, 0).get().alpha, 128)
	try expect_equal(back.pixel(0, 1).get().alpha, 255)
	try expect_equal(back.pixel(2, 0).get().green, 20)

test "bmp bit fields decode independent layouts and reject malformed masks":
	// Reversed channel order with alpha in a 108-byte header.
	reversed := decode_image(
		hex_decode(
			"424d7e000000000000007a0000006c0000000100000001000000010020000300000004000000130b0000130b00000000000000000000ff00000000ff00000000ff00000000ff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a141e28",
			none
		).get()
	).get().pixel(0, 0).get()
	try expect_equal(
		[reversed.red, reversed.green, reversed.blue, reversed.alpha], [10, 20, 30, 40]
	)

	// Three masks after a 40-byte header leave the image without alpha.
	plain := decode_image(
		hex_decode(
			"424d460000000000000042000000280000000100000001000000010020000300000004000000130b0000130b000000000000000000000000ff0000ff0000ff0000001e140a00",
			none
		).get()
	).get().pixel(0, 0).get()
	try expect_equal(
		[plain.red, plain.green, plain.blue, plain.alpha], [10, 20, 30, 255]
	)

	rejected := [
		// Red, green and blue share bits.
		"424d7e000000000000007a0000006c0000000100000001000000010020000300000004000000130b0000130b00000000000000000000ff000000ff000000ff000000000000ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001020304",
		// Alpha shares bits with green.
		"424d7e000000000000007a0000006c0000000100000001000000010020000300000004000000130b0000130b000000000000000000000000ff0000ff0000ff00000000ff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001020304",
		// No green mask.
		"424d7e000000000000007a0000006c0000000100000001000000010020000300000004000000130b0000130b000000000000000000000000ff0000000000ff000000000000ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001020304",
		// Non-contiguous green mask.
		"424d7e000000000000007a0000006c0000000100000001000000010020000300000004000000130b0000130b000000000000000000000000ff0000550000ff000000000000ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001020304",
		// A 40-byte header cut inside its masks.
		"424d460000000000000042000000280000000100000001000000010020000300000004000000130b0000130b000000000000000000000000ff0000ff",
	]
	for hex in rejected: try expect_equal(
		decode_image(hex_decode(hex, none).get()).is_ok(), false
	)

test "bmp fully transparent image stays transparent":
	var img = new_image(1, 1, ColorMode.Rgba).get()
	img.set_pixel(0, 0, Rgba(1, 2, 3, 0))

	back := decode_image(encode_image(img, ImageFormat.Bmp).get()).get()
	try expect_equal(back.pixel(0, 0).get().alpha, 0)

test "bmp 24-bit rgb is unchanged":
	var img = new_image(3, 2, ColorMode.Rgb).get()
	img.set_pixel(2, 1, Rgba(9, 8, 7))

	data := encode_image(img, ImageFormat.Bmp).get()
	try expect_equal(data.get(14).to_int(), 40)
	try expect_equal(decode_image(data).get().pixel(2, 1).get().blue, 7)

test "bmp legacy 32-bit with zero fourth bytes is opaque":
	// 1x1, BI_RGB, 32-bit, pixel B=30 G=20 R=10 A=0.
	data := hex_decode(
		"424d3a0000000000000036000000280000000100000001000000010020000000000004000000130b0000130b000000000000000000001e140a00",
		none
	).get()
	px := decode_image(data).get().pixel(0, 0).get()
	try expect_equal([px.red, px.green, px.blue, px.alpha], [10, 20, 30, 255])

test "truncated rejected":
	data := encode_image(new_image(4, 4, ColorMode.Rgb).get(), ImageFormat.Ppm).get()
	cut := data.slice(0, data.length() - 1).get()
	try expect_equal(decode_image(cut).is_ok(), false)

test "png decodes every independent vector":
	for v in vectors():
		img := decode_image(hex_decode(v.png, none).get()).get()
		try expect_equal(img.width, v.width)
		try expect_equal(img.height, v.height)

		for y in 0..v.height:
			for x in 0..v.width:
				at := (y * v.width + x) * 4
				c := img.pixel(x, y).get()
				try expect_equal(
					[c.red, c.green, c.blue, c.alpha], v.rgba.slice(at, at + 4).get()
				)

test "png encode decodes back":
	var img = new_image(7, 5, ColorMode.Rgba).get()
	for y in 0..5:
		for x in 0..7:
			img.set_pixel(x, y, Rgba(x * 30, y * 50, (x * y) % 256, 255 - x))

	back := decode_image(encode_image(img, ImageFormat.Png).get()).get()
	try expect_equal(back.pixels, img.pixels)

test "jpeg decodes libjpeg vectors within tolerance":
	for v in jpeg_vectors():
		img := decode_image(hex_decode(v.jpeg, none).get()).get()
		try expect_equal(img.width, v.width)
		try expect_equal(img.height, v.height)
		try expect_equal(img.channel_count(), v.channels)

		var worst = 0

		for i in 0..v.pixels.length():
			d := img.pixels[i].to_int() - v.pixels[i]
			a := if d < 0: 0 - d else: d
			if a > worst: worst = a

		if worst > v.tolerance: try fail("{v.name}: max error {worst} > {v.tolerance}")

test "jpeg encode round trips close to the source":
	var img = new_image(37, 29, ColorMode.Rgb).get()
	for y in 0..29:
		for x in 0..37:
			img.set_pixel(x, y, Rgba(x * 6, y * 8, 128 + (x - y) * 2))

	for chroma in [Chroma.Full, Chroma.Quarter]:
		for interval in [0, 3]:
			data := encode_jpeg(
				img,
				JpegOptions(
					quality: 95, chroma: chroma, restart_interval: interval
				)
			).get()
			back := decode_image(data).get()
			try expect_equal(back.width, 37)

			var worst = 0

			for i in 0..img.pixels.length():
				d := img.pixels[i].to_int() - back.pixels[i].to_int()
				a := if d < 0: 0 - d else: d
				if a > worst: worst = a

			if worst > 16: try fail("worst error {worst} for interval {interval}")

test "jpeg gray round trip and alpha rejection":
	var img = new_image(9, 9, ColorMode.Gray).get()
	for i in 0..9:
		img.set_pixel(i, i, Rgba(250, 250, 250))

	back := decode_image(encode_jpeg(img, JpegOptions(quality: 100)).get()).get()
	try expect_equal(back.channel_count(), 1)
	try expect_equal(encode_jpeg(new_image(2, 2, ColorMode.Rgba).get()).is_ok(), false)
