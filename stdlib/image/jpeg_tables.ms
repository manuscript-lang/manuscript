// Tables and small helpers shared by the JPEG decoder (`jpeg.ms`) and encoder
// (`jpeg_encode.ms`).

// Zigzag scan order of the 64 coefficients in an 8x8 block.
export jpeg_zigzag := [
	0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41,
	34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23,
	30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63
]
// Fixed-point (x4096) 8-point transform matrix: row x, column u is c(u)/2 *
// cos((2x+1)u*pi/16).
export jpeg_dct_matrix := [
	1448,
	2008,
	1892,
	1702,
	1448,
	1138,
	784,
	400,
	1448,
	1702,
	784,
	-400,
	-1448,
	-2008,
	-1892,
	-1138,
	1448,
	1138,
	-784,
	-2008,
	-1448,
	400,
	1892,
	1702,
	1448,
	400,
	-1892,
	-1138,
	1448,
	1702,
	-784,
	-2008,
	1448,
	-400,
	-1892,
	1138,
	1448,
	-1702,
	-784,
	2008,
	1448,
	-1138,
	-784,
	2008,
	-1448,
	-400,
	1892,
	-1702,
	1448,
	-1702,
	784,
	400,
	-1448,
	2008,
	-1892,
	1138,
	1448,
	-2008,
	1892,
	-1702,
	1448,
	-1138,
	784,
	-400,
]

// A canonical Huffman table in the decoding form of JPEG Annex F.

// Clamps `value` to 0 through `high`.
export fn jpeg_clamp(value: Int, high: Int) Int:
	return if value < 0: 0 else: (if value > high: high else: value)

// Returns `count` zero integers.
export fn jpeg_zeros(count: Int) List[Int]:
	return [0].repeated(count)
