import Bytes from "@std/bytes.ms"
import (ArchiveEntry, ArchiveLimits, NativeDecoder, NativeEncoder) from "@std/io/archive.ms"

export extern fn msstd_compress_encoder_new(format: String, level: Int) NativeEncoder!

export extern fn msstd_compress_encoder_push(encoder: NativeEncoder, data: Bytes) Bytes

export extern fn msstd_compress_encoder_end(encoder: NativeEncoder) Bytes

export extern fn msstd_compress_decoder_new(format: String, max_bytes: Int?) NativeDecoder!

export extern fn msstd_compress_decoder_push(decoder: NativeDecoder, data: Bytes) Bytes!

export extern fn msstd_compress_decoder_end(decoder: NativeDecoder) Bytes!

export extern fn msstd_archive_pack(
    entries: List[ArchiveEntry],
    format: String,
    max_bytes: Int?
) Bytes!

export extern fn msstd_archive_unpack(
    data: Bytes,
    format: String,
    limits: ArchiveLimits?
) List[ArchiveEntry]!

export extern fn msstd_compress_compress(
    data: Bytes,
    format: String,
    level: Int,
    max_bytes: Int?
) Bytes!

export extern fn msstd_compress_decompress(
    data: Bytes,
    format: String,
    max_bytes: Int?
) Bytes!
