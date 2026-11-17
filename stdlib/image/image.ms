import (
	Bytes from "@std/bytes.ms",
	decode_bmp, encode_bmp from "@std/image/bmp.ms",
	Raster,
	byte,
	max_of,
	min_of,
	pixel_count,
	unsupported,
	zeroed from "@std/image/codec.ms",
	decode_jpeg from "@std/image/jpeg.ms",
	jpeg_encode from "@std/image/jpeg_encode.ms",
	decode_png, encode_png from "@std/image/png.ms",
	decode_ppm, encode_ppm from "@std/image/ppm.ms",
)

/*
Raster images as one flat, interleaved byte buffer, decoded from and encoded to PNG, JPEG, BMP and PPM/PGM.

An `Image` owns `pixels`: row-major, `channels` bytes per pixel, no padding. The byte of
channel `c` at `(x, y)` is `pixels[(y * width + x) * channels + c]`.

    img := decode_image(read_file("photo.jpg").wait().get())?
    small := img.resize(img.width / 4, img.height / 4)?
    png := encode_image(small, ImageFormat.Png)?

Decoding never faults on hostile input. Malformed data is an `Error` of kind `EBADMSG`, an unsupported
feature (arithmetic-coded JPEG, RLE BMP) is `ENOTSUP`, and a size past `max_pixels` or the hard
ceiling of 2^30 pixels is `EOVERFLOW`. Headers are validated against the input length before any
pixel buffer is allocated. PNG inflation stops at the size the header implies. `max_pixels` is
optional; pass it when decoding untrusted files, because a small valid file can still describe a
large image (a compressed PNG of zeros, for example).

16-bit PNG samples keep their high byte. JPEG decoding matches libjpeg within 2 levels per channel
(fancy chroma upsampling included); EXIF orientation and ICC profiles are not interpreted.
*/

// The channels stored for each pixel.
export enum ColorMode:
	Gray  // One luminance byte per pixel, 0 black to 255 white.
	GrayAlpha  // Two bytes per pixel: luminance, then alpha (0 transparent to 255 opaque).
	Rgb  // Three bytes per pixel: red, green, blue, each 0 to 255.
	Rgba  // Red, green, blue, then alpha (not premultiplied).

// The file formats `decode_image` recognizes and `encode_image` writes.
export enum ImageFormat:
	Jpeg  // JPEG: baseline and progressive decode (grayscale, YCbCr, CMYK/YCCK), baseline encode.
	Png  // PNG: every color type and bit depth, Adam7 interlacing; 16-bit samples keep their high byte.
	Ppm  // Netpbm binary P5 (gray) and P6 (RGB), 8-bit.
	Bmp  // Windows bitmap: 1, 4, 8, 24 and 32-bit uncompressed decode; 24-bit (or 32-bit with alpha) encode.

// A width-by-height raster. Build one with `new_image`, `decode_image`, or the
// transforms below. Example:
// `img := new_image(2, 2, ColorMode.Rgb).get(); img.pixel(0, 0)` is opaque black.
export type Image:
	// Columns, at least 1.
	width: Int
	// Rows, at least 1.
	height: Int
	// The channel layout of `pixels`.
	mode: ColorMode
	// `width * height * channels` bytes, row-major.
	pixels: List[UInt8]

// Number of byte channels per pixel.
fn Image.channel_count() Int:
	return color_channels(self.mode)

// The pixel at `(x, y)` as RGBA, or `none` outside the image.
fn Image.pixel(x: Int, y: Int) Rgba?:
	if x < 0 or y < 0 or x >= self.width or y >= self.height: return none

	n := color_channels(self.mode)
	at := (y * self.width + x) * n
	p := self.pixels

	match self.mode:
		Gray: return Rgba(p[at].to_int(), p[at].to_int(), p[at].to_int(), 255)
		GrayAlpha: return Rgba(
			p[at].to_int(),
			p[at].to_int(),
			p[at].to_int(),
			p[at + 1].to_int(),
		)
		Rgb: return Rgba(p[at].to_int(), p[at + 1].to_int(), p[at + 2].to_int(), 255)
		Rgba: return Rgba(
			p[at].to_int(),
			p[at + 1].to_int(),
			p[at + 2].to_int(),
			p[at + 3].to_int(),
		)

// Writes `color` at `(x, y)`, converting to the image's mode; returns false outside
// the image.
fn var Image.set_pixel(x: Int, y: Int, color: Rgba) Bool:
	if x < 0 or y < 0 or x >= self.width or y >= self.height: return false

	n := color_channels(self.mode)
	at := (y * self.width + x) * n
	luma := (color.red * 299 + color.green * 587 + color.blue * 114) / 1000

	match self.mode:
		Gray:
			self.pixels[at] = byte(luma)
		GrayAlpha:
			self.pixels[at] = byte(luma)
			self.pixels[at + 1] = byte(color.alpha)
		Rgb:
			self.pixels[at] = byte(color.red)
			self.pixels[at + 1] = byte(color.green)
			self.pixels[at + 2] = byte(color.blue)
		Rgba:
			self.pixels[at] = byte(color.red)
			self.pixels[at + 1] = byte(color.green)
			self.pixels[at + 2] = byte(color.blue)
			self.pixels[at + 3] = byte(color.alpha)

	return true

// Copies the pixels of `area`; `ERANGE` when it leaves the image or is empty.
fn Image.crop(area: Rect) Image!:
	if area.width < 1 or area.height < 1 or area.x < 0 or area.y < 0:
		return error(Error("image: crop area is empty or negative", kind: "ERANGE"))
	if area.x > self.width - area.width or area.y > self.height - area.height:
		return error(Error("image: crop area leaves the image", kind: "ERANGE"))

	n := color_channels(self.mode)
	var out = List[UInt8](reserve: area.width * area.height * n)

	for row in 0..area.height:
		start := ((area.y + row) * self.width + area.x) * n
		for i in 0..area.width * n:
			out.append(self.pixels[start + i])

	return ok(Image(area.width, area.height, self.mode, out))

// Mirrors left to right.
fn Image.flip_horizontal() Image:
	n := color_channels(self.mode)
	var out = List[UInt8](reserve: self.pixels.length())

	for y in 0..self.height:
		for x in 0..self.width:
			at := (y * self.width + self.width - 1 - x) * n
			for c in 0..n:
				out.append(self.pixels[at + c])

	return Image(self.width, self.height, self.mode, out)

// Mirrors top to bottom.
fn Image.flip_vertical() Image:
	n := color_channels(self.mode)
	row := self.width * n
	var out = List[UInt8](reserve: self.pixels.length())

	for y in 0..self.height:
		start := (self.height - 1 - y) * row
		for i in 0..row:
			out.append(self.pixels[start + i])

	return Image(self.width, self.height, self.mode, out)

// Rotates a quarter turn clockwise; the result is `height` wide and `width` tall.
fn Image.rotate90() Image:
	n := color_channels(self.mode)
	var out = List[UInt8](reserve: self.pixels.length())

	for y in 0..self.width:
		for x in 0..self.height:
			at := ((self.height - 1 - x) * self.width + y) * n
			for c in 0..n:
				out.append(self.pixels[at + c])

	return Image(self.height, self.width, self.mode, out)

// Rotates a half turn.
fn Image.rotate180() Image:
	n := color_channels(self.mode)
	if not rotation_shape(self, n): return self.flip_horizontal().flip_vertical()

	var out = List[UInt8](reserve: self.pixels.length())

	for y in 0..self.height:
		for x in 0..self.width:
			at := ((self.height - 1 - y) * self.width + self.width - 1 - x) * n
			for c in 0..n:
				out.append(self.pixels[at + c])

	return Image(self.width, self.height, self.mode, out)

// Rotates three quarter turns clockwise (one counter-clockwise).
fn Image.rotate270() Image:
	n := color_channels(self.mode)
	if not rotation_shape(self, n): return (
		self
		.rotate90()
		.flip_horizontal()
		.flip_vertical()
	)

	var out = List[UInt8](reserve: self.pixels.length())

	for y in 0..self.width:
		for x in 0..self.height:
			at := (x * self.width + self.width - 1 - y) * n
			for c in 0..n:
				out.append(self.pixels[at + c])

	return Image(self.height, self.width, self.mode, out)

// Converts to `target`: gray from RGB uses Rec. 601 luma, gray expands by
// repeating, missing alpha is opaque, and dropping alpha keeps the stored color (no
// compositing).
fn Image.convert(target: ColorMode) Image:
	if target == self.mode: return Image(
		self.width,
		self.height,
		self.mode,
		self.pixels.clone(),
	)

	count := self.width * self.height
	m := color_channels(target)
	var out = List[UInt8](reserve: count * m)

	for i in 0..count:
		c := self.pixel(i % self.width, i / self.width).get(Rgba(0, 0, 0, 255))
		luma := (c.red * 299 + c.green * 587 + c.blue * 114) / 1000

		match target:
			Gray:
				out.append(byte(luma))
			GrayAlpha:
				out.append(byte(luma))
				out.append(byte(c.alpha))
			Rgb:
				out.append(byte(c.red))
				out.append(byte(c.green))
				out.append(byte(c.blue))
			Rgba:
				out.append(byte(c.red))
				out.append(byte(c.green))
				out.append(byte(c.blue))
				out.append(byte(c.alpha))

	return Image(self.width, self.height, target, out)

// Scales to `width` by `height`; `ERANGE` for a non-positive size, `EOVERFLOW` past
// `max_pixels`.
fn Image.resize(
	width: Int,
	height: Int,
	method: Resampling = Resampling.Bilinear,
	max_pixels: Int? = none,
) Image!:
	count := pixel_count(width, height, max_pixels)?
	n := color_channels(self.mode)
	var out = List[UInt8](reserve: count * n)

	for y in 0..height:
		for x in 0..width:
			match method:
				Nearest:
					sx := x * self.width / width
					sy := y * self.height / height
					at := (sy * self.width + sx) * n
					for c in 0..n:
						out.append(self.pixels[at + c])
				Bilinear:
					// Sample centers, in 1/256ths, clamped to the source.
					fx := max_of(0, ((2 * x + 1) * self.width * 128) / width - 128)
					fy := max_of(0, ((2 * y + 1) * self.height * 128) / height - 128)
					x0 := min_of(fx / 256, self.width - 1)
					y0 := min_of(fy / 256, self.height - 1)
					x1 := min_of(x0 + 1, self.width - 1)
					y1 := min_of(y0 + 1, self.height - 1)
					wx := if x0 == x1: 0 else: fx % 256
					wy := if y0 == y1: 0 else: fy % 256

					for c in 0..n:
						a := self.pixels[(y0 * self.width + x0) * n + c].to_int()
						b := self.pixels[(y0 * self.width + x1) * n + c].to_int()
						d := self.pixels[(y1 * self.width + x0) * n + c].to_int()
						e := self.pixels[(y1 * self.width + x1) * n + c].to_int()
						top := a * (256 - wx) + b * wx
						bottom := d * (256 - wx) + e * wx
						out.append(
							byte(
								(
									top * (256 - wy)
									+ bottom * wy
									+ 32768
								) / 65536
							)
						)

	return ok(Image(width, height, self.mode, out))

// Public fields permit malformed images. Keep their original composed behavior,
// including overflow checks on empty shapes, without multiplying unchecked sizes.
fn rotation_shape(image: Image, channels: Int) Bool:
	if image.width < 1 or image.height < 1: return false
	if image.pixels.length() % channels != 0: return false

	pixels := image.pixels.length() / channels
	return pixels % image.height == 0 and pixels / image.height == image.width

// One RGBA sample, each channel 0 to 255.
export type Rgba:
	// Red level, 0 to 255; writes clamp.
	red: Int
	// Green level, 0 to 255; writes clamp.
	green: Int
	// Blue level, 0 to 255; writes clamp.
	blue: Int
	// Opacity, 0 transparent to 255 opaque (the default).
	alpha: Int = 255

// Chroma resolution of an encoded JPEG.
export enum Chroma:
	Full  // 4:4:4, no subsampling.
	Quarter  // 4:2:0, chroma at half width and height (smaller files).

// Settings for `encode_jpeg`.
export type JpegOptions:
	// 1 (smallest) to 100 (best); outside that range `encode_jpeg` fails with `EINVAL`.
	quality: Int = 85
	// Chroma resolution for color images; gray images ignore it.
	chroma: Chroma = Chroma.Quarter
	// MCUs between restart markers, or 0 for none. Markers let readers recover from
	// damage.
	restart_interval: Int = 0

// A rectangle in pixels: top-left corner and size.
export type Rect:
	// Column of the left edge, counted from 0.
	x: Int
	// Row of the top edge, counted from 0.
	y: Int
	// Columns covered; at least 1.
	width: Int
	// Rows covered; at least 1.
	height: Int

// How `resize` samples the source.
export enum Resampling:
	Nearest  // Fastest; keeps hard edges.
	Bilinear  // Weighted average of the four nearest pixels.

// Number of byte channels in `mode`.
export fn color_channels(mode: ColorMode) Int:
	match mode:
		Gray: return 1
		GrayAlpha: return 2
		Rgb: return 3
		Rgba: return 4

// Checks dimensions against `max_pixels` and the hard ceiling, returning the pixel
// count.
// Creates an opaque black image (alpha modes are fully opaque); `EINVAL` for a
// non-positive size, `EOVERFLOW` past `max_pixels`.
export fn new_image(
	width: Int,
	height: Int,
	mode: ColorMode,
	max_pixels: Int? = none,
) Image!:
	if width < 1 or height < 1: return error(
		Error("image: dimensions must be positive", kind: "EINVAL")
	)

	count := pixel_count(width, height, max_pixels)?
	n := color_channels(mode)
	var pixels = zeroed(count * n)
	if mode == ColorMode.GrayAlpha or mode == ColorMode.Rgba:
		for i in 0..count:
			pixels[i * n + n - 1] = byte(255)
	return ok(Image(width, height, mode, pixels))

// ---- format detection ----

// Names the format of `data` from its leading bytes, or `none`.
export fn detect_image_format(data: Bytes) ImageFormat?:
	if data.length() >= 2:
		a := data.get(0).to_int()
		b := data.get(1).to_int()
		if a == 255 and b == 216: return ImageFormat.Jpeg
		if a == 137 and b == 80: return ImageFormat.Png
		if a == 66 and b == 77: return ImageFormat.Bmp
		if a == 80 and (b == 53 or b == 54): return ImageFormat.Ppm

	return none

fn color_mode(channels: Int) ColorMode:
	if channels == 1: return ColorMode.Gray
	if channels == 2: return ColorMode.GrayAlpha
	if channels == 3: return ColorMode.Rgb

	return ColorMode.Rgba

fn image_of(raster: Raster) Image:
	return Image(
		raster.width,
		raster.height,
		color_mode(raster.channels),
		raster.pixels,
	)

// Decodes any supported format. `max_pixels` rejects larger images with `EOVERFLOW`
// before any allocation.
export fn decode_image(data: Bytes, max_pixels: Int? = none) Image!:
	format := detect_image_format(data)

	if f := format:
		match f:
			Jpeg: return decode_jpeg(data, max_pixels).map(image_of)
			Png: return decode_png(data, max_pixels).map(image_of)
			Ppm: return decode_ppm(data, max_pixels).map(image_of)
			Bmp: return decode_bmp(data, max_pixels).map(image_of)

	return error(unsupported("unrecognized image format"))

// Encodes `image` as `format`.
export fn encode_image(image: Image, format: ImageFormat) Bytes!:
	match format:
		Jpeg: return encode_jpeg(image, JpegOptions())
		Png: return encode_png(
			image.width,
			image.height,
			color_channels(image.mode),
			image.pixels,
		)
		Ppm: return encode_ppm(
			image.width,
			image.height,
			color_channels(image.mode),
			image.pixels,
		)
		Bmp: return encode_bmp(
			image.width,
			image.height,
			color_channels(image.mode),
			image.pixels,
		)

// Encodes baseline JPEG: gray stays gray, Rgb uses YCbCr with the chosen chroma
// resolution. Alpha images fail with
// `EINVAL`; convert or composite first.
export fn encode_jpeg(image: Image, options: JpegOptions = JpegOptions()) Bytes!:
	return jpeg_encode(
		image.width,
		image.height,
		color_channels(image.mode),
		image.pixels,
		options.quality,
		options.chroma == Chroma.Quarter,
		options.restart_interval,
	)
