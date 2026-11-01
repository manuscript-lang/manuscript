import BinaryError, Bytes from "@std/bytes.ms"

# Fixed-width number codecs for Bytes and BytesBuilder, written in Manuscript over one word reader and four float bit casts.
# They apply wherever Bytes and BytesBuilder are used, without an import.
# The `width` bytes at `at` (1, 2, 4 or 8) as an unsigned number; eight bytes keep their bit pattern as an Int.
export extern fn msrt_bytes_read_word(
    data: Bytes,
    at: Int,
    width: Int,
    little: Bool
) Int!BinaryError

export extern fn msrt_float_from_bits(bits: Int) Float

export extern fn msrt_float_to_bits(value: Float) Int

export extern fn msrt_float32_from_bits(bits: Int) Float

export extern fn msrt_float32_to_bits(value: Float) Int

export extern fn msrt_bits_bit_and(left: Int, right: Int) Int

export extern fn msrt_bits_shift_right(value: Int, count: Int) Int

export extern fn msrt_bytes_join(parts: List[Bytes]) Bytes

export extern fn msrt_bytes_values(data: Bytes) List[UInt8]
