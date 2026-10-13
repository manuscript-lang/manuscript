# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"

# Errors returned when compressed data is unsupported, invalid, or exceeds a limit.
export type CompressionError:
    # Compression level is outside 0..9, or a supplied encoded/decoded byte budget is negative.
    case InvalidInput
    # Compressed framing, checksum, payload or trailing data is invalid for the chosen format.
    case InvalidData
    # Encoded or decompressed output exceeds the supplied byte budget.
    case LimitExceeded
    # A String selector is not exactly gzip, zlib or deflate; typed selectors avoid spelling errors.
    case Unsupported
    # An explicit implementation-supplied compression diagnostic; native codecs use specific cases.
    case Failed(
        # Original diagnostic text, returned unchanged by message().
        message: String
    )

# Compresses using exactly `gzip`, `zlib`, or raw `deflate` (case-sensitive).
# Other formats return Unsupported; level must be 0..9 (0 stores data), else InvalidInput.
# `max_bytes` bounds the encoded output when supplied.
export fn compress(
    data: Bytes,
    format: String,
    level: Int,
    max_bytes: Optional[Int64] = none
) -> Result[Bytes, CompressionError]:

# Decompresses exactly `gzip`, `zlib`, or raw `deflate` (case-sensitive); others return Unsupported.
# Stops when the supplied output limit is reached.
export fn decompress(
    data: Bytes,
    format: String,
    max_bytes: Optional[Int64] = none
) -> Result[Bytes, CompressionError]:

impl Error for CompressionError:
    # Returns original Failed text, or a compression-prefixed diagnostic for other cases.
    fn message() -> String:

# Selects a supported compression format; Deflate is raw DEFLATE without a wrapper.
# Existing compress/decompress format: String calls remain available.
export type CompressionFormat:
    # DEFLATE data wrapped in GZIP headers and a checksum trailer.
    case Gzip
    # DEFLATE data with ZLIB header and Adler-32 checksum framing.
    case Zlib
    # Raw DEFLATE without framing.
    case Deflate
    # Compresses with level 0..9 and the same optional output budget/domain errors as compress.
    fn compress(
        data: Bytes,
        level: Int,
        max_bytes: Optional[Int64] = none
    ) -> Result[Bytes, CompressionError]:
    # Decompresses with the same cumulative output limit and validation as decompress.
    fn decompress(
        data: Bytes,
        max_bytes: Optional[Int64] = none
    ) -> Result[Bytes, CompressionError]:
