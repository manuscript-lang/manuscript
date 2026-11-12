// conform: tags=testing,tier-stdlib
// conform: phase=test
import ColorMode, Image, new_image from "@std/image/image.ms"

fn sample(width: Int, height: Int, mode: ColorMode) Image:
	var image = new_image(width, height, mode).get()
	for i in 0..image.pixels.length():
		image.pixels[i] = ((i * 73 + i / 7) % 256).to_uint8().get()
	return image

fn check_equal(a: Image, b: Image) Unit!:
	if (
		a.width != b.width
		or a.height != b.height
		or a.mode != b.mode
		or a.pixels != b.pixels
	):
		return error(Error("rotation differs"))
	return ok(unit)

test "rotations preserve every channel and their inverse":
	for mode in [ColorMode.Gray, ColorMode.GrayAlpha, ColorMode.Rgb, ColorMode.Rgba]:
		for width in [1, 2, 3, 7, 32]:
			for height in [1, 2, 3, 9, 31]:
				image := sample(width, height, mode)
				check_equal(image.rotate180(), image.flip_horizontal().flip_vertical())?
				check_equal(
					image.rotate270(),
					image.rotate90().flip_horizontal().flip_vertical(),
				)?
				check_equal(image.rotate180().rotate180(), image)?
				check_equal(image.rotate270().rotate90(), image)?

				var turned = image.rotate180()
				turned.pixels[0] = ((turned.pixels[0].to_int() + 1) % 256).to_uint8().get()
				check_equal(image, sample(width, height, mode))?

				var other = image.rotate270()
				other.pixels[0] = ((other.pixels[0].to_int() + 1) % 256).to_uint8().get()
				check_equal(image, sample(width, height, mode))?

test "rotations retain empty and extra-buffer behavior":
	for image in [
		Image(0, 0, ColorMode.Rgba, []),
		Image(0, 3, ColorMode.Rgba, []),
		Image(-1, 2, ColorMode.Rgba, []),
		Image(2, -1, ColorMode.Rgba, []),
		Image(2, 2, ColorMode.Rgba, [1.to_uint8().get()].repeated(17)),
	]:
		check_equal(image.rotate180(), image.flip_horizontal().flip_vertical())?
		check_equal(
			image.rotate270(),
			image.rotate90().flip_horizontal().flip_vertical(),
		)?
