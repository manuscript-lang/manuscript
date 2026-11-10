import Bytes, BytesBuilder from "@std/bytes.ms"
import (
    bit_and,
    bit_or,
    shift_left,
    shift_right,
    shift_right_unsigned
) from "@std/math/math.ms"
import crc32 from "@std/data/checksum.ms"
import (compress, decompress, CompressionFormat) from "@std/io/archive.ms"

/*
Raster images as one flat, interleaved byte buffer, decoded from and encoded to PNG, JPEG, BMP and PPM/PGM.

An `Image` owns `pixels`: row-major, `channels` bytes per pixel, no padding. The byte of
channel `c` at `(x, y)` is `pixels[(y * width + x) * channels + c]`.

    img := try decode_image(read_file("photo.jpg").wait().get())
    small := try img.resize(img.width / 4, img.height / 4)
    png := try encode_image(small, ImageFormat.Png)

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

// The file formats `decode` recognizes and `encode` writes.
export enum ImageFormat:
    Jpeg  // JPEG: baseline and progressive decode (grayscale, YCbCr, CMYK/YCCK), baseline encode.
    Png  // PNG: every color type and bit depth, Adam7 interlacing; 16-bit samples keep their high byte.
    Ppm  // Netpbm binary P5 (gray) and P6 (RGB), 8-bit.
    Bmp  // Windows bitmap: 1, 4, 8, 24 and 32-bit uncompressed decode; 24-bit (or 32-bit with alpha) encode.

// A width-by-height raster. Build one with `new_image`, `decode`, or the transforms below.
// Example: `img := new_image(2, 2, ColorMode.Rgb).get(); img.pixel(0, 0)` is opaque black.
export type Image:
    // Columns, at least 1.
    width: Int
    // Rows, at least 1.
    height: Int
    // The channel layout of `pixels`.
    mode: ColorMode
    // `width * height * channels` bytes, row-major.
    pixels: List[UInt8]

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
    // MCUs between restart markers, or 0 for none. Markers let readers recover from damage.
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

// The largest pixel count any decoder or constructor accepts; keeps index arithmetic far from overflow.
HARD_MAX_PIXELS := 1073741824

fn bad(message: String) Error:
    return Error("image: {message}", kind: "EBADMSG")

fn unsupported(message: String) Error:
    return Error("image: {message}", kind: "ENOTSUP")

fn too_big(message: String) Error:
    return Error("image: {message}", kind: "EOVERFLOW")

fn byte(value: Int) UInt8:
    if value <= 0: return 0.to_uint8().get(0)
    if value >= 255: return 255.to_uint8().get(0)

    return value.to_uint8().get(0)

// Number of byte channels in `mode`.
export fn color_channels(mode: ColorMode) Int:
    match mode:
        Gray: return 1
        GrayAlpha: return 2
        Rgb: return 3
        Rgba: return 4

// Checks dimensions against `max_pixels` and the hard ceiling, returning the pixel count.
fn pixel_count(width: Int, height: Int, max_pixels: Int?) Int!:
    if width < 1 or height < 1: return error(bad("dimensions must be positive"))
    if width > HARD_MAX_PIXELS / height: return error(
        too_big("{width}x{height} is too large")
    )

    count := width * height
    if limit := max_pixels:
        if count > limit: return error(
            too_big("{width}x{height} exceeds {limit} pixels")
        )
    return ok(count)

fn zeroed(count: Int) List[UInt8]:
    return [0.to_uint8().get(0)].repeated(count)

// Creates an opaque black image (alpha modes are fully opaque); `EINVAL` for a non-positive size, `EOVERFLOW` past `max_pixels`.
export fn new_image(
    width: Int,
    height: Int,
    mode: ColorMode,
    max_pixels: Int? = none
) Image!:
    if width < 1 or height < 1: return error(
        Error("image: dimensions must be positive", kind: "EINVAL")
    )

    count := try pixel_count(width, height, max_pixels)
    n := color_channels(mode)
    var pixels = zeroed(count * n)
    if mode == ColorMode.GrayAlpha or mode == ColorMode.Rgba:
        for i in 0..count:
            pixels[i * n + n - 1] = byte(255)
    return ok(Image(width, height, mode, pixels))

impl Image:
    // Number of byte channels per pixel.
    fn channel_count() Int:
        return color_channels(self.mode)

    // The pixel at `(x, y)` as RGBA, or `none` outside the image.
    fn pixel(x: Int, y: Int) Rgba?:
        if x < 0 or y < 0 or x >= self.width or y >= self.height: return none

        n := color_channels(self.mode)
        at := (y * self.width + x) * n
        p := self.pixels

        match self.mode:
            Gray: return Rgba(p[at].to_int(), p[at].to_int(), p[at].to_int(), 255)
            GrayAlpha: return Rgba(
                p[at].to_int(), p[at].to_int(), p[at].to_int(), p[at + 1].to_int()
            )
            Rgb: return Rgba(
                p[at].to_int(), p[at + 1].to_int(), p[at + 2].to_int(), 255
            )
            Rgba: return Rgba(
                p[at].to_int(), p[at + 1].to_int(), p[at + 2].to_int(),
                p[at + 3].to_int()
            )

    // Writes `color` at `(x, y)`, converting to the image's mode; returns false outside the image.
    var fn set_pixel(x: Int, y: Int, color: Rgba) Bool:
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
    fn crop(area: Rect) Image!:
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
    fn flip_horizontal() Image:
        n := color_channels(self.mode)
        var out = List[UInt8](reserve: self.pixels.length())

        for y in 0..self.height:
            for x in 0..self.width:
                at := (y * self.width + self.width - 1 - x) * n
                for c in 0..n:
                    out.append(self.pixels[at + c])

        return Image(self.width, self.height, self.mode, out)

    // Mirrors top to bottom.
    fn flip_vertical() Image:
        n := color_channels(self.mode)
        row := self.width * n
        var out = List[UInt8](reserve: self.pixels.length())

        for y in 0..self.height:
            start := (self.height - 1 - y) * row
            for i in 0..row:
                out.append(self.pixels[start + i])

        return Image(self.width, self.height, self.mode, out)

    // Rotates a quarter turn clockwise; the result is `height` wide and `width` tall.
    fn rotate90() Image:
        n := color_channels(self.mode)
        var out = List[UInt8](reserve: self.pixels.length())

        for y in 0..self.width:
            for x in 0..self.height:
                at := ((self.height - 1 - x) * self.width + y) * n
                for c in 0..n:
                    out.append(self.pixels[at + c])

        return Image(self.height, self.width, self.mode, out)

    // Rotates a half turn.
    fn rotate180() Image:
        return self.flip_horizontal().flip_vertical()

    // Rotates three quarter turns clockwise (one counter-clockwise).
    fn rotate270() Image:
        return self.rotate90().rotate180()

    // Converts to `target`: gray from RGB uses Rec. 601 luma, gray expands by repeating, missing alpha is opaque,
    // and dropping alpha keeps the stored color (no compositing).
    fn convert(target: ColorMode) Image:
        if target == self.mode: return Image(
            self.width, self.height, self.mode, self.pixels.clone()
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

    // Scales to `width` by `height`; `ERANGE` for a non-positive size, `EOVERFLOW` past `max_pixels`.
    fn resize(
        width: Int,
        height: Int,
        method: Resampling = Resampling.Bilinear,
        max_pixels: Int? = none
    ) Image!:
        count := try pixel_count(width, height, max_pixels)
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
                        fy := max_of(
                            0,
                            (
                                (2 * y + 1)
                                * self.height
                                * 128
                            ) / height - 128
                        )
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
                                        top * (
                                            256
                                            - wy
                                        )
                                        + bottom * wy
                                        + 32768
                                    ) / 65536
                                )
                            )

        return ok(Image(width, height, self.mode, out))

fn max_of(a: Int, b: Int) Int:
    return if a > b: a else: b

fn min_of(a: Int, b: Int) Int:
    return if a < b: a else: b

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

// Decodes any supported format. `max_pixels` rejects larger images with `EOVERFLOW` before any allocation.
export fn decode_image(data: Bytes, max_pixels: Int? = none) Image!:
    format := detect_image_format(data)

    if f := format:
        match f:
            Jpeg: return decode_jpeg(data, max_pixels)
            Png: return decode_png(data, max_pixels)
            Ppm: return decode_ppm(data, max_pixels)
            Bmp: return decode_bmp(data, max_pixels)

    return error(unsupported("unrecognized image format"))

// Encodes `image` as `format`.
export fn encode_image(image: Image, format: ImageFormat) Bytes!:
    match format:
        Jpeg: return encode_jpeg(image, JpegOptions())
        Png: return encode_png(image)
        Ppm: return encode_ppm(image)
        Bmp: return encode_bmp(image)

// ---- PPM / PGM ----

fn is_space(b: Int) Bool:
    return b == 32 or b == 9 or b == 10 or b == 13 or b == 11 or b == 12

// Reads one header integer from `at`, skipping whitespace and # comments; returns (value, next offset).
fn ppm_number(data: Bytes, start: Int) List[Int]!:
    var at = start

    while at < data.length():
        b := data.get(at).to_int()

        if b == 35:
            while at < data.length() and data.get(at).to_int() != 10:
                at += 1
        else if is_space(b):
            at += 1
        else:
            break

    var value = 0
    var digits = 0

    while at < data.length():
        b := data.get(at).to_int()
        if b < 48 or b > 57: break

        value = value * 10 + b - 48
        if value > 4294967295: return error(too_big("header number too large"))

        digits += 1
        at += 1

    if digits == 0: return error(bad("expected a number in the PNM header"))

    return ok([value, at])

fn decode_ppm(data: Bytes, max_pixels: Int?) Image!:
    if data.length() < 2: return error(bad("truncated PNM header"))

    kind := data.get(1).to_int()
    n := if kind == 54: 3 else: 1
    wide := try ppm_number(data, 2)
    tall := try ppm_number(data, wide[1])
    peak := try ppm_number(data, tall[1])
    width := wide[0]
    height := tall[0]
    maxval := peak[0]
    if maxval < 1 or maxval > 65535: return error(
        bad("PNM maxval {maxval} out of range")
    )

    // Exactly one whitespace byte separates the header from the raster.
    start := peak[1] + 1
    if peak[1] >= data.length() or not is_space(data.get(peak[1]).to_int()):
        return error(bad("missing separator after PNM header"))

    count := try pixel_count(width, height, max_pixels)
    sample := if maxval > 255: 2 else: 1

    // The raster must be present in full before anything is allocated.
    if count > (data.length() - start) / (n * sample): return error(
        bad("truncated PNM raster")
    )

    total := count * n
    var pixels = List[UInt8](reserve: total)

    for i in 0..total:
        raw := data.get(start + i * sample).to_int()

        if sample == 2:
            pixels.append(byte(raw))
        else if maxval == 255:
            pixels.append(byte(raw))
        else:
            pixels.append(byte((min_of(raw, maxval) * 255 + maxval / 2) / maxval))

    return ok(
        Image(
            width, height, if n == 3: ColorMode.Rgb else: ColorMode.Gray, pixels
        )
    )

fn encode_ppm(image: Image) Bytes!:
    if image.mode == ColorMode.Rgba or image.mode == ColorMode.GrayAlpha:
        return error(
            Error(
                "image: PNM cannot store alpha; convert to Rgb or Gray first",
                kind: "EINVAL"
            )
        )

    var out = BytesBuilder()
    magic := if image.mode == ColorMode.Rgb: "P6" else: "P5"
    out.append_bytes("{magic}\n{image.width} {image.height}\n255\n".to_bytes())
    for b in image.pixels:
        out.append(b)
    return ok(out.build())

// ---- BMP ----

fn le16(data: Bytes, at: Int) Int:
    return data.get(at).to_int() + data.get(at + 1).to_int() * 256

fn le32(data: Bytes, at: Int) Int:
    return le16(data, at) + le16(data, at + 2) * 65536

fn signed32(value: Int) Int:
    return if value >= 2147483648: value - 4294967296 else: value

fn decode_bmp(data: Bytes, max_pixels: Int?) Image!:
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
    if compression != 0: return error(unsupported("BMP compression {compression}"))
    if bits != 1 and bits != 4 and bits != 8 and bits != 24 and bits != 32:
        return error(unsupported("BMP depth {bits}"))
    if width < 1 or width > 2147483647 or height > 2147483647:
        return error(bad("BMP dimensions out of range"))

    count := try pixel_count(width, height, max_pixels)

    // Palette entries sit between the header and the pixels.
    entry := if header == 12: 3 else: 4
    var palette_size = 0

    if bits <= 8:
        palette_size = if colors == 0: shift_left(1, bits) else: colors
        if palette_size > shift_left(1, bits): return error(
            bad("BMP palette too large")
        )

    palette_at := 14 + header
    if palette_at + palette_size * entry > data.length():
        return error(bad("truncated BMP palette"))

    row := ((width * bits + 31) / 32) * 4
    if offset < palette_at or offset > data.length(): return error(
        bad("BMP pixel offset out of range")
    )
    if height > (data.length() - offset) / row: return error(
        bad("truncated BMP pixel data")
    )

    alpha := bits == 32
    mode := if alpha: ColorMode.Rgba else: ColorMode.Rgb
    m := color_channels(mode)
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
                        data.get(base + bit / 8).to_int(), shift
                    ),
                    shift_left(1, bits) - 1
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

    // 32-bit BMP alpha is often unused zero; treat an all-zero channel as opaque.
    if alpha and not any_alpha:
        for i in 0..count:
            pixels[i * 4 + 3] = byte(255)
    return ok(Image(width, height, mode, pixels))

fn put16(var out: BytesBuilder, value: Int) Unit:
    out.append(byte(bit_and(value, 255)))
    out.append(byte(bit_and(shift_right_unsigned(value, 8), 255)))

fn put32(var out: BytesBuilder, value: Int) Unit:
    put16(var out, bit_and(value, 65535))
    put16(var out, bit_and(shift_right_unsigned(value, 16), 65535))

fn encode_bmp(image: Image) Bytes!:
    if image.width > 2147483647 or image.height > 2147483647:
        return error(too_big("BMP dimensions too large"))

    alpha := image.mode == ColorMode.Rgba or image.mode == ColorMode.GrayAlpha
    bytes_per := if alpha: 4 else: 3
    row := ((image.width * bytes_per * 8 + 31) / 32) * 4
    size := 54 + row * image.height
    if size > 4294967295: return error(too_big("BMP is larger than 4 GiB"))

    var out = BytesBuilder()
    out.append(byte(66))
    out.append(byte(77))
    put32(var out, size)
    put32(var out, 0)
    put32(var out, 54)
    put32(var out, 40)
    put32(var out, image.width)
    put32(var out, image.height)
    put16(var out, 1)
    put16(var out, bytes_per * 8)
    put32(var out, 0)
    put32(var out, row * image.height)
    put32(var out, 2835)
    put32(var out, 2835)
    put32(var out, 0)
    put32(var out, 0)

    for y in 0..image.height:
        sy := image.height - 1 - y

        for x in 0..image.width:
            c := image.pixel(x, sy).get(Rgba(0, 0, 0, 255))
            out.append(byte(c.blue))
            out.append(byte(c.green))
            out.append(byte(c.red))
            if alpha: out.append(byte(c.alpha))

        for _pad in 0..row - image.width * bytes_per:
            out.append(byte(0))

    return ok(out.build())

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

// The seven Adam7 passes as [x start, y start, x step, y step]; non-interlaced is one pass.
fn png_passes(interlaced: Bool) List[List[Int]]:
    if not interlaced: return [[0, 0, 1, 1]]

    return [
        [0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4],
        [1, 0, 2, 2], [0, 1, 1, 2]
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

fn decode_png(data: Bytes, max_pixels: Int?) Image!:
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

            // Reject oversized images from the header alone, before reading any further.
            _ := try pixel_count(width, height, max_pixels)
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

    count := try pixel_count(width, height, max_pixels)
    if color == 3 and palette.is_empty(): return error(
        bad("indexed PNG without a palette")
    )

    samples := png_channels(color)
    bits_per_pixel := samples * depth
    expected := png_raw_size(width, height, bits_per_pixel, interlaced)

    // The inflate budget is the size the header implies, so a bomb stops at that bound.
    raw := try decompress(idat.build(), CompressionFormat.Zlib, expected)
    if raw.length() != expected: return error(
        bad("PNG pixel data is {raw.length()} bytes, expected {expected}")
    )

    // Output layout. A tRNS chunk adds alpha to gray, RGB and indexed images.
    keyed := not transparency.is_empty()
    var mode = ColorMode.Rgba
    if color == 0: mode = if keyed: ColorMode.GrayAlpha else: ColorMode.Gray
    if color == 2: mode = if keyed: ColorMode.Rgba else: ColorMode.Rgb
    if color == 3: mode = if keyed: ColorMode.Rgba else: ColorMode.Rgb
    if color == 4: mode = ColorMode.GrayAlpha

    m := color_channels(mode)
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
                                cur[bit / 8], 8 - depth - bit % 8
                            ),
                            top
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

    return ok(Image(width, height, mode, pixels))

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

// Filters one row with the type whose residuals have the smallest absolute sum (the usual heuristic).
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

fn encode_png(image: Image) Bytes!:
    if image.width > 2147483647 or image.height > 2147483647:
        return error(too_big("PNG dimensions too large"))

    n := color_channels(image.mode)
    var color = 6

    match image.mode:
        Gray: color = 0
        GrayAlpha: color = 4
        Rgb: color = 2
        Rgba: color = 6

    var raw = BytesBuilder()
    row_bytes := image.width * n
    var prev = [0].repeated(row_bytes)

    for y in 0..image.height:
        var row = List[Int](reserve: row_bytes)
        for i in 0..row_bytes:
            row.append(image.pixels[y * row_bytes + i].to_int())
        for v in filter_row(row, prev, n):
            raw.append(byte(v))
        prev = row

    var header = BytesBuilder()
    put_be32(var header, image.width)
    put_be32(var header, image.height)
    header.append(byte(8))
    header.append(byte(color))
    header.append(byte(0))
    header.append(byte(0))
    header.append(byte(0))

    var out = BytesBuilder()
    out.append_bytes(Bytes([137, 80, 78, 71, 13, 10, 26, 10]))
    png_chunk(var out, "IHDR", header.build())

    packed := try compress(raw.build(), CompressionFormat.Zlib)
    png_chunk(var out, "IDAT", packed)
    png_chunk(var out, "IEND", Bytes([]))
    return ok(out.build())

// ---- JPEG ----

zigzag := [
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41,
    34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23,
    30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63
]
// Fixed-point (x4096) 8-point transform matrix: row x, column u is c(u)/2 * cos((2x+1)u*pi/16).
dct_matrix := [
    1448, 2008, 1892, 1702, 1448, 1138, 784, 400, 1448, 1702, 784, -400, -1448, -2008,
    -1892, -1138, 1448, 1138, -784, -2008, -1448, 400, 1892, 1702, 1448, 400, -1892,
    -1138, 1448, 1702, -784, -2008, 1448, -400, -1892, 1138, 1448, -1702, -784, 2008,
    1448, -1138, -784, 2008, -1448, -400, 1892, -1702, 1448, -1702, 784, 400, -1448,
    2008, -1892, 1138, 1448, -2008, 1892, -1702, 1448, -1138, 784, -400
]

// A canonical Huffman table in the decoding form of JPEG Annex F.
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

impl JpegBits:
    var fn bit(data: Bytes) Int:
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
                    // A marker ends the entropy-coded segment; reading into it is corruption.
                    self.failed = true
                    return 0

                self.pos += 2
            else:
                self.pos += 1

            self.acc = b
            self.count = 8

        self.count -= 1
        return bit_and(shift_right_unsigned(self.acc, self.count), 1)

    var fn receive(data: Bytes, n: Int) Int:
        var v = 0
        for i in 0..n:
            v = v * 2 + self.bit(data)
        return v

    // Decodes one symbol, or -1 after setting `failed`.
    var fn symbol(data: Bytes, table: JpegHuffman) Int:
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
    scan: JpegScan
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

                comp.coef[base + zigzag[zi]] = jpeg_extend(
                    bits.receive(data, size), size
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
                comp.coef[base], shift_left(1, scan.al)
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

                comp.coef[base + zigzag[zi]] = (
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
                at := base + zigzag[zi]

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

                comp.coef[base + zigzag[zi]] = value

            zi += 1
            if bits.failed: return

    if bits.eobrun > 0:
        while zi <= scan.se:
            at := base + zigzag[zi]
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
                            dct_matrix[x * 8 + u]
                            * f
                            * comp.quant[y * 8 + u]
                        )

                    tmp[y * 8 + x] = shift_right(sum + 32, 6)

            for x in 0..8:
                for y in 0..8:
                    var sum = 0
                    for v in 0..8:
                        sum += dct_matrix[y * 8 + v] * tmp[v * 8 + x]
                    plane[(by * 8 + y) * stride + bx * 8 + x] = byte(
                        shift_right(sum + 131072, 18) + 128
                    )

    return plane

fn decode_jpeg(data: Bytes, max_pixels: Int?) Image!:
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

                        table[zigzag[zi]] = v

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

                    table := try build_huffman(counts, values)

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

                _total := try pixel_count(width, height, max_pixels)
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
                            data.get(q).to_int(), h, v, tq, 0, 0, List[Int](),
                            List[Int](), 0
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

                // Blocks per component this scan codes, and the allocation budget check.
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
                        comps[c].coef = zeroed_ints(
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
                                data, var bits, var comps[c], base,
                                dc_tables[dc_ids[m]], ac_tables[ac_ids[m]], scan
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
                                        scan
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
                (width * c.h + hmax - 1) / hmax, (height * c.v + vmax - 1) / vmax
            ]
        )

    mode := if zi == 1: ColorMode.Gray else: ColorMode.Rgb
    m := color_channels(mode)
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
                    ].v == 0
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
                // Four components: Adobe CMYK/YCCK store inverted ink, so a stored value acts as its own transmittance.
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

    return ok(Image(width, height, mode, pixels))

// First offset at or after `from` that starts a marker other than a stuffed zero, fill or restart.
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

// Reads component sample (x, y) of the full-resolution grid. A 2:1 ratio uses libjpeg's triangle filter ("fancy"
// upsampling) so output matches libjpeg; other ratios replicate the nearest sample.
fn jpeg_sample(
    plane: List[UInt8],
    stride: Int,
    span: List[Int],
    y: Int,
    x: Int,
    hr: Int,
    vr: Int,
    exact: Bool
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
            py * stride + clamp_to(
                if x % 2 == 0: px - 1 else: px + 1, last_x
            )
        ].to_int()
        return (3 * here + near + (if x % 2 == 0: 1 else: 2)) / 4

    ny := clamp_to(if y % 2 == 0: py - 1 else: py + 1, last_y)

    if hr == 1:
        here := plane[py * stride + px].to_int()
        near := plane[ny * stride + px].to_int()
        return (3 * here + near + (if y % 2 == 0: 1 else: 2)) / 4

    nx := clamp_to(if x % 2 == 0: px - 1 else: px + 1, last_x)
    here := 3 * plane[py * stride + px].to_int() + plane[ny * stride + px].to_int()
    near := 3 * plane[py * stride + nx].to_int() + plane[ny * stride + nx].to_int()
    return (3 * here + near + (if x % 2 == 0: 8 else: 7)) / 16

fn clamp_to(value: Int, high: Int) Int:
    return if value < 0: 0 else: (if value > high: high else: value)

fn zeroed_ints(count: Int) List[Int]:
    return [0].repeated(count)

fn ycc_to_rgb(y: Int, cb: Int, cr: Int) List[Int]:
    u := cb - 128
    v := cr - 128
    return [
        y + shift_right(91881 * v + 32768, 16),
        y - shift_right(22554 * u + 46802 * v + 32768, 16),
        y + shift_right(116130 * u + 32768, 16)
    ]

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
    var code = zeroed_ints(256)
    var size = zeroed_ints(256)
    var next = 0
    var index = 0

    for length in 1..17:
        for _slot in 0..counts.get(length - 1):
            code[values.get(index)] = next
            size[values.get(index)] = length
            next += 1
            index += 1

        next *= 2

    return JpegCodes(code, size)

type JpegWriter:
    out: BytesBuilder
    acc: Int
    count: Int

impl JpegWriter:
    var fn put(code: Int, size: Int) Unit:
        self.acc = bit_or(shift_left(self.acc, size), code)
        self.count += size

        while self.count >= 8:
            b := bit_and(shift_right_unsigned(self.acc, self.count - 8), 255)
            self.out.append(byte(b))
            if b == 255: self.out.append(byte(0))
            self.count -= 8

        self.acc = bit_and(self.acc, shift_left(1, self.count) - 1)

    // Pads the partial byte with 1-bits, as the format requires before a marker.
    var fn align() Unit:
        if self.count > 0: self.put(shift_left(1, 8 - self.count) - 1, 8 - self.count)

fn bit_length(value: Int) Int:
    var v = if value < 0: 0 - value else: value
    var n = 0

    while v > 0:
        n += 1
        v /= 2

    return n

// Forward DCT and quantization of the 8x8 block at (x0, y0); returns 64 levels in zigzag order.
fn jpeg_forward(
    plane: List[Int],
    stride: Int,
    x0: Int,
    y0: Int,
    quant: List[Int]
) List[Int]:
    var tmp = zeroed_ints(64)

    for y in 0..8:
        for u in 0..8:
            var sum = 0
            for x in 0..8:
                sum += (
                    dct_matrix[x * 8 + u]
                    * (plane[(y0 + y) * stride + x0 + x] - 128)
                )
            tmp[y * 8 + u] = sum

    var levels = zeroed_ints(64)

    for zi in 0..64:
        at := zigzag[zi]
        v := at / 8
        u := at % 8
        var sum = 0
        for y in 0..8:
            sum += dct_matrix[y * 8 + v] * tmp[y * 8 + u]

        q := quant.get(zi)
        half := q * 8388608
        scale := q * 16777216
        levels[zi] = if sum >= 0: (sum + half) / scale else: 0 - ((half - sum) / scale)

    return levels

fn jpeg_emit(
    var w: JpegWriter, levels: List[Int], previous: Int, dc: JpegCodes, ac: JpegCodes
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
        table.append(clamp_to(max_of((base.get(zi) * scale + 50) / 100, 1), 255))
    return table

// Encodes baseline JPEG: gray stays gray, Rgb uses YCbCr with the chosen chroma resolution. Alpha images fail with
// `EINVAL`; convert or composite first.
export fn encode_jpeg(image: Image, options: JpegOptions = JpegOptions()) Bytes!:
    if image.mode == ColorMode.Rgba or image.mode == ColorMode.GrayAlpha:
        return error(
            Error(
                "image: JPEG cannot store alpha; convert to Rgb or Gray first",
                kind: "EINVAL"
            )
        )
    if options.quality < 1 or options.quality > 100:
        return error(Error("image: JPEG quality must be 1 to 100", kind: "EINVAL"))
    if options.restart_interval < 0 or options.restart_interval > 65535:
        return error(
            Error(
                "image: JPEG restart interval must be 0 to 65535", kind: "EINVAL"
            )
        )
    if image.width > 65535 or image.height > 65535:
        return error(too_big("JPEG dimensions are limited to 65535"))

    color := image.mode == ColorMode.Rgb
    sub := color and options.chroma == Chroma.Quarter
    unit_size := if sub: 16 else: 8
    mcus_x := (image.width + unit_size - 1) / unit_size
    mcus_y := (image.height + unit_size - 1) / unit_size
    pw := mcus_x * unit_size
    ph := mcus_y * unit_size

    // Full-resolution planes, edge-replicated to whole MCUs.
    var luma = zeroed_ints(pw * ph)
    var cb = zeroed_ints(if color: pw * ph else: 0)
    var cr = zeroed_ints(if color: pw * ph else: 0)
    n := color_channels(image.mode)

    for y in 0..ph:
        sy := min_of(y, image.height - 1)

        for x in 0..pw:
            at := (sy * image.width + min_of(x, image.width - 1)) * n

            if color:
                r := image.pixels[at].to_int()
                g := image.pixels[at + 1].to_int()
                b := image.pixels[at + 2].to_int()
                luma[y * pw + x] = shift_right(
                    19595 * r + 38470 * g + 7471 * b + 32768, 16
                )
                cb[y * pw + x] = shift_right(
                    0 - 11059 * r - 21709 * g + 32768 * b + 8421376, 16
                )
                cr[y * pw + x] = shift_right(
                    32768 * r - 27439 * g - 5329 * b + 8421376, 16
                )
            else:
                luma[y * pw + x] = image.pixels[at].to_int()

    var cw = pw

    if sub:
        cw = pw / 2

        var small_cb = zeroed_ints(cw * (ph / 2))
        var small_cr = zeroed_ints(cw * (ph / 2))

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

    q_luma := jpeg_scaled(jpeg_base_luma, options.quality)
    q_chroma := jpeg_scaled(jpeg_base_chroma, options.quality)
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
    put16_be(var frame, image.height)
    put16_be(var frame, image.width)
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

    if options.restart_interval > 0:
        var dri = BytesBuilder()
        put16_be(var dri, options.restart_interval)
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
            if (
                options.restart_interval > 0
                and mcu > 0
                and mcu % options.restart_interval == 0
            ):
                w.align()
                w.out.append(byte(255))
                w.out.append(byte(208 + (mcu / options.restart_interval - 1) % 8))
                p_y = 0
                p_cb = 0
                p_cr = 0

            blocks_y := if sub: 2 else: 1

            for by in 0..blocks_y:
                for bx in 0..blocks_y:
                    levels := jpeg_forward(
                        luma, pw, mx * unit_size + bx * 8, my * unit_size + by * 8,
                        q_luma
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
