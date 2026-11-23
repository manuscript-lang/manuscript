// Guard: JPEG and PNG encode and decode stay linear in the pixel count (#4197).
import (
	ColorMode,
	ImageFormat,
	decode_image,
	encode_image,
	encode_jpeg,
	new_image
) from "@std/image/image.ms"

fn main() Void!:
	w := 128
	h := 128
	var img = new_image(w, h, ColorMode.Rgb)?

	for y in 0..h:
		for x in 0..w:
			at := (y * w + x) * 3
			img.pixels[at] = ((x * 3 + y * 5) % 256).to_uint8() or 0
			img.pixels[at + 1] = ((x + y * 2) % 256).to_uint8() or 0
			img.pixels[at + 2] = ((x * 7 + y) % 256).to_uint8() or 0

	png := encode_image(img, ImageFormat.Png)?
	jpg := encode_jpeg(img)?
	print(
		f"{png.length()} {jpg.length()} {(decode_image(png)?).width} {(decode_image(jpg)?).width}"
	)
