import (
	ColorMode, Image, new_image from "@std/image/image.ms",
	arguments from "@std/os/env.ms",
	monotonic from "@std/time.ms",
)

fn direct180(image: Image) Image:
	return image.rotate180()

fn direct270(image: Image) Image:
	return image.rotate270()

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

fn verify() Unit!:
	for mode in [ColorMode.Gray, ColorMode.GrayAlpha, ColorMode.Rgb, ColorMode.Rgba]:
		for width in [1, 2, 3, 7, 32]:
			for height in [1, 2, 3, 9, 31]:
				image := sample(width, height, mode)
				check_equal(direct180(image), base180(image))?
				check_equal(direct270(image), base270(image))?
				check_equal(direct180(direct180(image)), image)?
				check_equal(direct270(image).rotate90(), image)?

	print("verified 100 images, both rotations and inverse identities")
	return ok(unit)

fn base180(image: Image) Image:
	return image.flip_horizontal().flip_vertical()

fn base270(image: Image) Image:
	return image.rotate90().flip_horizontal().flip_vertical()

fn control90(image: Image) Image:
	return image.rotate90()

fn select(kind: String) fn(Image) Image:
	if kind == "direct180": return direct180
	if kind == "direct270": return direct270
	if kind == "base270": return base270
	if kind == "control90": return control90

	return base180

fn work(image: Image, operation: fn(Image) Image, repeats: Int) Int:
	var checksum = 0

	for i in 0..repeats:
		out := operation(image)
		checksum += out.pixels[i % out.pixels.length()].to_int()

	return checksum

fn main() Unit!:
	args := arguments()
	if args.is_empty(): return verify()

	if args[0] == "malformed":
		width := args[2].parse_int().get()
		height := args[3].parse_int().get()
		count := args[4].parse_int().get()
		image := Image(
			width,
			height,
			ColorMode.Rgba,
			[1.to_uint8().get()].repeated(count),
		)
		operation := select(args[1])
		out := operation(image)
		print("{out.width} {out.height} {out.pixels}")
		return ok(unit)

	kind := args[0]
	width := args[1].parse_int().get()
	height := args[2].parse_int().get()
	repeats := args[3].parse_int().get()
	mode := if args.length() > 4: args[4].parse_int().get() else: 3
	image := sample(
		width,
		height,
		[ColorMode.Gray, ColorMode.GrayAlpha, ColorMode.Rgb, ColorMode.Rgba][
			mode
		],
	)
	check_equal(direct180(image), base180(image))?
	check_equal(direct270(image), base270(image))?

	operation := select(kind)
	work(image, operation, 1)

	start := monotonic()
	checksum := work(image, operation, repeats)
	elapsed := monotonic().difference(start).nanos
	print("{kind} {width} {height} {repeats} {elapsed} {checksum}")
	return ok(unit)
