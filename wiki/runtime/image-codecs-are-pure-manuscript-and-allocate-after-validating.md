[Wiki](../index.md) › [Runtime](index.md)

# Image codecs are pure Manuscript and allocate only after validating the header

Decision: `@std/image/image.ms` implements PNG, JPEG, BMP and PPM in Manuscript on top of `Bytes`, `BytesBuilder`, `archive.ms` zlib and `checksum.ms` crc32; no Rust and no crate. Limits stay optional (`max_pixels: Int? = none`).

Verified: a decoder compares the header's implied size with the real input before it allocates (PPM/BMP raster length, PNG inflate budget equal to the header-implied size, JPEG blocks per scan at most 8 bits of remaining data), rejects oversized dimensions at the header (PNG at IHDR), and returns `EBADMSG`, `ENOTSUP` or `EOVERFLOW`. Mutation fuzzing (`image-fuzz.ms`, 15k inputs, PNG CRCs repaired so mutations get past the gate) found no faults; hostile-header cases are fixed tests. JPEG output stays within 2 levels of libjpeg, which needs libjpeg's triangle ("fancy") chroma upsampling, not replication (error 29 without it).

Apply when: adding a decoder or format to the image module, or any binary parser fed untrusted bytes.
Evidence: [image.ms](../../stdlib/image/image.ms), [image tests](../../tests/conformance/fixtures/e2e/stdlib/image.ms), [fuzz](../../tests/conformance/fixtures/e2e/stdlib/image-fuzz.ms), vector generators beside them (Pillow and an independent PNG writer).
Verify: `ms test tests/conformance/fixtures/e2e/stdlib/image.ms` and `image-fuzz.ms`.

Pitfalls found while writing it: exported names `decode` and `encode` made the checker suggest this module's import in unrelated golden diagnostics, so exports carry the format domain (`decode_image`); a stored `Bytes` field moves the whole input, so pass the input to methods instead of keeping it in a reader struct; `put16` helpers are little-endian for BMP and JPEG needs `put16_be`.
