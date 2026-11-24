import (
	ColorMode,
	ImageFormat,
	JpegOptions,
	decode_image,
	encode_image,
	encode_jpeg,
	new_image from "@std/image/image.ms",
	monotonic from "@std/time.ms",
)

fn main() Void! {
	w := 2048
	h := 2048
	var img = new_image(w, h, ColorMode.Rgb)?
	var y = 0

	while y < h {
		var x = 0

		while x < w {
			at := (y * w + x) * 3
			img.pixels[at] = ((x * 3 + y * 5 + (x * y) / 512) % 256).to_uint8() or 0
			img.pixels[at + 1] = ((x + y * 2 + (x + y * 3) % 251) % 256).to_uint8() or 0
			img.pixels[at + 2] = ((x * 7 + y + (x / 8) * (y / 8)) % 256).to_uint8() or 0
			x += 1
		}

		y += 1
	}

	var t = monotonic()
	png := encode_image(img, ImageFormat.Png)?
	print(
		f"png encode {monotonic().difference(t).to_milliseconds()} ms {png.length()} bytes"
	)
	t = monotonic()

	back := decode_image(png)?
	print(f"png decode {monotonic().difference(t).to_milliseconds()} ms {back.width}")
	t = monotonic()

	jpg := encode_jpeg(img)?
	print(
		f"jpeg encode {monotonic().difference(t).to_milliseconds()} ms {jpg.length()} bytes"
	)
	t = monotonic()

	jb := decode_image(jpg)?
	print(f"jpeg decode {monotonic().difference(t).to_milliseconds()} ms {jb.width}")
}
