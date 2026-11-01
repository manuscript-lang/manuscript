import Bytes from "@std/bytes.ms"

export extern fn msstd_checksum_crc32(data: Bytes) Int

export extern fn msstd_checksum_crc32_update(initial: Int, data: Bytes) Int

export extern fn msstd_checksum_adler32_update(initial: Int, data: Bytes) Int
