import (
	Bytes from "@std/bytes.ms",
	ArchiveEntry, NativeDecoder, NativeEncoder from "@std/io/archive.ms",
)

// Native unpack bounds; `unpack` builds them from `ArchiveOptions`.
export type ArchiveLimits:
	max_entries Int?
	max_entry_bytes Int?
	max_total_bytes Int?

export extern fn msstd_compress_encoder_new(
	format String,
	level Int,
) move NativeEncoder!

export extern fn msstd_compress_encoder_push(
	encoder NativeEncoder,
	data Bytes,
) move Bytes

export extern fn msstd_compress_encoder_end(encoder NativeEncoder) move Bytes

export extern fn msstd_compress_decoder_new(
	format String,
	max_bytes Int?,
) move NativeDecoder!

export extern fn msstd_compress_decoder_push(
	decoder NativeDecoder,
	data Bytes,
) move Bytes!

export extern fn msstd_compress_decoder_end(decoder NativeDecoder) move Bytes!

export extern fn msstd_archive_pack(
	entries List[ArchiveEntry],
	format String,
	max_bytes Int?,
) move Bytes!

export extern fn msstd_archive_unpack(
	data Bytes,
	format String,
	limits ArchiveLimits,
) move List[ArchiveEntry]!

export extern fn msstd_compress_compress(
	data Bytes,
	format String,
	level Int,
	max_bytes Int?,
) move Bytes!

export extern fn msstd_compress_decompress(
	data Bytes,
	format String,
	max_bytes Int?,
) move Bytes!
