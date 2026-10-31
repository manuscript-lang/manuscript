import ReadStream from "@std/io.ms"

export extern fn msstd_archive_compress_stream(
    format: String,
    input: ReadStream,
    level: Int
) ReadStream

export extern fn msstd_archive_decompress_stream(
    format: String,
    input: ReadStream,
    max_bytes: Int?
) ReadStream
