import Bytes from "@std/bytes.ms"

/*
Shared pieces of the image codecs: the decoded raster the codecs exchange with `@std/image/image.ms`,
error constructors, and size checks. Use `@std/image/image.ms`; this module is its implementation detail.
*/

// A decoded or to-be-encoded raster: `channels` is 1 (gray), 2 (gray, alpha), 3 (RGB)
// or 4 (RGBA) and `pixels` holds `width * height * channels` bytes, row-major.
export type Raster:
	// Columns, at least 1.
	width: Int
	// Rows, at least 1.
	height: Int
	// Bytes per pixel, 1 to 4; even counts carry alpha.
	channels: Int
	// Row-major interleaved bytes.
	pixels: List[UInt8]

// The largest pixel count any decoder or constructor accepts; keeps index arithmetic
// far from overflow.
HARD_MAX_PIXELS := 1073741824

// Builds an `EBADMSG` error for malformed image data.
export fn bad(message: String) Error:
	return Error("image: {message}", kind: "EBADMSG")

// Builds an `ENOTSUP` error for a valid but unsupported image feature.
export fn unsupported(message: String) Error:
	return Error("image: {message}", kind: "ENOTSUP")

// Builds an `EOVERFLOW` error for dimensions past a limit.
export fn too_big(message: String) Error:
	return Error("image: {message}", kind: "EOVERFLOW")

// Clamps `value` to 0 through 255 as a byte.
export fn byte(value: Int) UInt8:
	if value <= 0: return 0.to_uint8().get(0)
	if value >= 255: return 255.to_uint8().get(0)

	return value.to_uint8().get(0)

// Checks dimensions against `max_pixels` and the 2^30 hard ceiling; returns the pixel
// count or `EBADMSG` or `EOVERFLOW`.
export fn pixel_count(width: Int, height: Int, max_pixels: Int?) Int!:
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

// Returns `count` zero bytes.
export fn zeroed(count: Int) List[UInt8]:
	return [0.to_uint8().get(0)].repeated(count)

// Returns the larger of `a` and `b`.
export fn max_of(a: Int, b: Int) Int:
	return if a > b: a else: b

// Returns the smaller of `a` and `b`.
export fn min_of(a: Int, b: Int) Int:
	return if a < b: a else: b
