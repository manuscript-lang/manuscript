import Bytes from "@std/bytes.ms"
import (
    msstd_checksum_crc32,
    msstd_checksum_crc32_update,
    msstd_checksum_adler32_update
) from "@std/internal/checksum.ms"

# Computes CRC-32/ISO-HDLC (IEEE, as used by ZIP and gzip) as an unsigned 32-bit value.
# Uses polynomial 0x04C11DB7 (reflected 0xEDB88320), reflected input/output,
# initial register 0xFFFFFFFF and final XOR 0xFFFFFFFF. Empty input returns zero.
# Reads the input without copying it. Detects accidental corruption; it does not authenticate data.
# `crc32("123456789".to_bytes())` returns 3421780262 (0xCBF43926).
export fn crc32(data: Bytes) UInt32:
    return msstd_checksum_crc32(data).to_uint32().get()

# Computes the RFC 1950 Adler-32 checksum used by zlib. Empty input returns one.
# Starting with a = 1 and b = 0, adds each byte to a and each a to b, modulo 65521;
# the result is b * 65536 + a. Reads the input without copying it.
# `adler32("Wikipedia".to_bytes())` returns 300286872 (0x11E60398).
export fn adler32(data: Bytes) UInt32:
    return msstd_checksum_adler32_update(1, data).to_uint32().get()

# An IEEE CRC-32 checksum built from ordered chunks, retaining no input bytes.
# `var sum = Crc32()` then `sum.update("123456789".to_bytes())` gives `sum.value()` = 3421780262.
# Reading the value does not reset it; create a new Crc32 to start over.
export type Crc32:
    # Accumulator state, initially the empty checksum. Use update() to append data.
    state: UInt32 = 0

impl Crc32:
    # Appends these bytes to the checksum; an empty chunk leaves it unchanged.
    var fn update(data: Bytes) Unit:
        self.state = msstd_checksum_crc32_update(self.state.to_int(), data).to_uint32().get()

    # Returns the current checksum without resetting or otherwise changing it.
    fn value() UInt32:
        return self.state

# An RFC 1950 Adler-32 checksum built from ordered chunks, retaining no input bytes.
# `var sum = Adler32()` then `sum.update("Wikipedia".to_bytes())` gives `sum.value()` = 300286872.
# Reading the value does not reset it; create a new Adler32 to start over.
export type Adler32:
    # Accumulator state, initially the empty checksum. Use update() to append data.
    state: UInt32 = 1

impl Adler32:
    # Appends these bytes to the checksum; an empty chunk leaves it unchanged.
    var fn update(data: Bytes) Unit:
        self.state = msstd_checksum_adler32_update(self.state.to_int(), data).to_uint32().get()

    # Returns the current checksum without resetting or otherwise changing it.
    fn value() UInt32:
        return self.state
