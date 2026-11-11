import (
	Bytes, BytesBuilder, join from "@std/bytes.ms",
	ReadStream, Transform, WriteStream, through from "@std/io/io.ms",

	ArchiveLimits,
	msstd_archive_pack,
	msstd_archive_unpack,
	msstd_compress_compress,
	msstd_compress_decoder_end,
	msstd_compress_decoder_new,
	msstd_compress_decoder_push,
	msstd_compress_decompress,
	msstd_compress_encoder_end,
	msstd_compress_encoder_new,
	msstd_compress_encoder_push from "@std/internal/archive.ms",
)

// One file or directory in an archive. Paths use forward slashes.
export type ArchiveEntry:
	// Relative forward-slash path; pack/unpack reject traversal, absolute paths and duplicate normalized names. Tar unpack also skips a bare `./` entry and strips a leading `./` from member names (as in `tar -cf x.tar .`); pack stays strict. Unpack returns directory paths without a trailing slash.
	path: String
	// File contents as immutable bytes; directory entries must carry empty bytes.
	data: Bytes
	// True for a directory entry rather than a regular file; links and special files are not supported.
	directory: Bool

// Bounds applied while unpacking untrusted archive data. Fields set to none add no budget.
export type ArchiveOptions:
	// Maximum unpacked entries, including directories.
	max_entries: Int? = none
	// Maximum unpacked bytes for each entry; zero admits only empty data.
	max_entry_bytes: Int? = none
	// Cumulative unpacked file bytes across all entries.
	max_bytes: Int? = none

// A supported archive format.
export enum ArchiveFormat:
	Zip  // ZIP files and directories.
	Tar  // TAR files and directories.

fn archive_format_name(format: ArchiveFormat) String:
	match format:
		Zip: return "zip"
		Tar: return "tar"

// Encodes entries as `format`. `max_bytes` bounds the encoded output when supplied.
export fn pack(
	entries: List[ArchiveEntry],
	format: ArchiveFormat,
	max_bytes: Int? = none
) Bytes!:
	return msstd_archive_pack(entries, archive_format_name(format), max_bytes)

// Decodes `format`, applying the entry and size bounds in `options`.
export fn unpack(
	data: Bytes,
	format: ArchiveFormat,
	options: ArchiveOptions = ArchiveOptions()
) List[ArchiveEntry]!:
	limits := ArchiveLimits(
		max_entries: options.max_entries, max_entry_bytes: options.max_entry_bytes,
		max_total_bytes: options.max_bytes
	)
	return msstd_archive_unpack(data, archive_format_name(format), limits)

// Selects a compression format; Deflate is raw DEFLATE without a wrapper.
export enum CompressionFormat:
	Gzip  // DEFLATE data wrapped in GZIP headers and a checksum trailer.
	Zlib  // DEFLATE data with ZLIB header and Adler-32 checksum framing.
	Deflate  // Raw DEFLATE without framing.

fn compression_format_name(format: CompressionFormat) String:
	match format:
		Gzip: return "gzip"
		Zlib: return "zlib"
		Deflate: return "deflate"

// Settings for `compress`: the DEFLATE level (0 to 9, default 6) and an optional budget on the encoded output bytes.
export type CompressOptions:
	// Compression level 0..9, where 0 stores data and 6 is balanced; other levels return EINVAL.
	level: Int = 6
	// Maximum encoded bytes; none adds no output budget.
	max_bytes: Int? = none

// Compresses `data` as `format`; `options.max_bytes` bounds the encoded output when supplied.
export fn compress(
	data: Bytes,
	format: CompressionFormat,
	options: CompressOptions = CompressOptions()
) Bytes!:
	return msstd_compress_compress(
		data, compression_format_name(format), options.level, options.max_bytes
	)

// Decompresses `format`, stopping with EOVERFLOW when `max_bytes` of output is exceeded.
export fn decompress(
	data: Bytes,
	format: CompressionFormat,
	max_bytes: Int? = none
) Bytes!:
	return msstd_compress_decompress(data, compression_format_name(format), max_bytes)

// A codec held by a stream step; `failure` is a construction error returned by every read.
export extern type NativeEncoder

// A native decompression codec held by a stream step.
export extern type NativeDecoder

type Compressing:
	encoder: NativeEncoder?
	failure: Error?

fn var Compressing.step(value: Bytes, var out: List[Bytes]) Unit!:
	if failure := self.failure: return error(failure.clone())

	if encoder := self.encoder:
		packed := msstd_compress_encoder_push(encoder, value)
		if not packed.is_empty(): out.append(packed)

fn var Compressing.finish(var out: List[Bytes]) Unit!:
	if failure := self.failure: return error(failure.clone())

	if encoder := self.encoder:
		out.append(msstd_compress_encoder_end(encoder))
	self.encoder = none

// Compresses a byte stream into `format`, chunk by chunk, holding only the codec's window. `level` defaults to 6
// and must be 0..9, otherwise reads fail with `EINVAL`. Closing the result closes `input`.
export fn compressed(
	input: ReadStream[Bytes],
	format: CompressionFormat,
	level: Int = 6
) ReadStream[Bytes]:
	made := msstd_compress_encoder_new(compression_format_name(format), level)
	var step = Compressing(encoder: none, failure: none)

	if made.is_error():
		step.failure = made.err()
	else:
		step.encoder = made.get()

	return through[Bytes, Bytes](input, step)

type Decompressing:
	decoder: NativeDecoder?
	failure: Error?

fn var Decompressing.step(value: Bytes, var out: List[Bytes]) Unit!:
	if failure := self.failure: return error(failure.clone())

	if decoder := self.decoder:
		plain := msstd_compress_decoder_push(decoder, value)?
		if not plain.is_empty(): out.append(plain)

fn var Decompressing.finish(var out: List[Bytes]) Unit!:
	if failure := self.failure: return error(failure.clone())

	if decoder := self.decoder:
		plain := msstd_compress_decoder_end(decoder)?
		if not plain.is_empty(): out.append(plain)

	self.decoder = none

// Decompresses a byte stream from `format`, chunk by chunk. Malformed or truncated data, or bytes after the payload, fail the read with
// `EBADMSG`; `max_bytes` bounds the total output and exceeding it fails with `EOVERFLOW`. Closing the
// result closes `input`.
export fn decompressed(
	input: ReadStream[Bytes],
	format: CompressionFormat,
	max_bytes: Int? = none
) ReadStream[Bytes]:
	made := msstd_compress_decoder_new(compression_format_name(format), max_bytes)
	var step = Decompressing(decoder: none, failure: none)

	if made.is_error():
		step.failure = made.err()
	else:
		step.decoder = made.get()

	return through[Bytes, Bytes](input, step)

// Reads the octal (or base-256) size field of a tar header block; -1 when the size is beyond any real member.
fn tar_size(block: Bytes) Int:
	first := block.get(124, 0).to_int()
	var size = 0

	if first >= 128:
		size = first - 128

		for i in 125..136:
			// Past 2^52 the size is not a real member; -1 lets the caller reject it before the arithmetic overflows.
			if size >= 4503599627370496: return -1

			size = size * 256 + block.get(i, 0).to_int()

		if size >= 4503599627370496: return -1

		return size

	for i in 124..136:
		digit := block.get(i, 0).to_int()
		if digit < 48 or digit > 55: continue

		size = size * 8 + (digit - 48)

	return size

// The decimal `size` among the `length key=value\n` records of a PAX extended header, or -1.
fn pax_size(data: Bytes) Int:
	var found = -1
	var pos = 0

	while pos < data.length():
		space := data.index_of_byte(32, pos)
		if space.is_none(): break

		var length = 0

		for i in pos..space.get():
			digit := data.get(i, 0).to_int()
			if digit < 48 or digit > 57 or i - pos > 9: return found

			length = length * 10 + digit - 48

		if length < 5 or pos + length > data.length(): break

		end := pos + length - 1
		eq := data.index_of_byte(61, space.get() + 1)

		if eq.is_some() and eq.get() < end:
			key := data.slice(space.get() + 1, eq.get()).get("".to_bytes())

			if key == "size".to_bytes():
				var value = 0
				var valid = eq.get() + 1 < end and end - eq.get() - 1 <= 15

				for i in eq.get() + 1..end:
					digit := data.get(i, 0).to_int()
					if digit < 48 or digit > 57: valid = false
					if valid: value = value * 10 + digit - 48

				if valid: found = value

		pos += length

	return found

fn tar_is_zero(block: Bytes) Bool:
	for byte in block.values():
		if byte != 0: return false
	return true

// Frames a tar byte stream into members (extension headers, the header and its data) and unpacks each one with
// `unpack`, so one entry at a time is in memory.
type TarEntries:
	options: ArchiveOptions
	buffer: Bytes
	count: Int
	total: Int
	done: Bool
	end: Bytes
	// Cleaned paths seen so far, the file paths among them, and every ancestor directory of a seen path.
	names: Set[String]
	files: Set[String]
	parents: Set[String]

// Fails with `EOVERFLOW` when a member of `size` data bytes exceeds `max_entry_bytes` or would take the archive past `max_bytes`.
fn TarEntries.check_size(size: Int) Unit!:
	over: Unit! := error(Error("archive: limit exceeded", kind: "EOVERFLOW"))
	if most := self.options.max_entry_bytes:
		if size > most: return over
	if most := self.options.max_bytes:
		if self.total + size > most: return over

// Bytes of the member at the start of the buffer, or 0 while its end has not arrived. Once the input has
// ended (`ended`), a final member whose data is complete but whose padding is short counts as whole,
// as `unpack` accepts it.
fn TarEntries.member_length(ended: Bool) Int!:
	var at = 0

	// A PAX `size` record replaces the size field of the header that follows it.
	var override = -1

	while true:
		if self.buffer.length() < at + 512: return ok(0)

		block := self.buffer.slice(at, at + 512)?
		flag := block.get(156, 0).to_int()
		var size = tar_size(block)
		var padded = 0
		if size < 0: return error(Error("archive: invalid archive", kind: "EBADMSG"))

		// 'x', 'g', 'L' and 'K' carry data for the header that follows them.
		extension := flag == 120 or flag == 103 or flag == 76 or flag == 75
		if not extension and override >= 0: size = override
		padded = (size + 511) / 512 * 512

		// Refuse a member that is over a limit from its header, before any of its data is buffered.
		if not extension and padded > 0:
			self.check_size(size)?
		at += 512
		if (
			flag == 53
			or flag == 49
			or flag == 50
			or flag == 51
			or flag == 52
			or flag == 54
			or flag == 55
		):
			padded = 0
		at += padded

		if self.buffer.length() < at:
			slack := if padded > 0: padded - size else: 0
			if ended and not extension and self.buffer.length() >= at - slack:
				return ok(self.buffer.length())

			return ok(0)

		if not extension: return ok(at)

		if flag == 120:
			start := at - padded
			records := self.buffer.slice(start, start + size)?
			found := pax_size(records)
			if found >= 0: override = found

	return ok(0)

// Applies `unpack`'s whole-archive path rules across members: no duplicate path, no file that is
// also a directory, and no entry below a file.
fn var TarEntries.admit(path: String, directory: Bool) Unit!:
	invalid: Unit! := error(Error("archive: invalid archive", kind: "EBADMSG"))
	if self.names.contains(path.clone()): return invalid
	if not directory and self.parents.contains(path.clone()): return invalid

	var dir = path.clone()

	while true:
		slash := dir.last_index_of("/")
		if slash.is_none(): break

		dir = dir.take(slash.get())
		if self.files.contains(dir.clone()): return invalid

		self.parents.add(dir.clone())

	if not directory: self.files.add(path.clone())
	self.names.add(path)

// Emits the members the buffer holds completely; `ended` says no more input will come.
fn var TarEntries.drain(var out: List[ArchiveEntry], ended: Bool) Unit!:
	while true:
		if (self.buffer.length() >= 512 and tar_is_zero(self.buffer.slice(0, 512)?)):
			self.done = true
			self.buffer = join([])
			break

		length := self.member_length(ended)?
		if length == 0: break

		var member = self.buffer.slice(0, length)?
		self.buffer = self.buffer.slice(length, self.buffer.length())?

		// Padding the archive ended inside is restored so the end blocks stay block-aligned.
		short := length % 512
		if short != 0: member = member.concat(self.end.slice(0, 512 - short)?)

		end := member.concat(self.end)

		for entry in unpack(end, ArchiveFormat.Tar, self.options)?:
			self.admit(entry.path.clone(), entry.directory)?
			self.count += 1
			self.total += entry.data.length()
			out.append(entry)

		if most := self.options.max_entries:
			if self.count > most: return error(
				Error("archive: limit exceeded", kind: "EOVERFLOW")
			)
		if most := self.options.max_bytes:
			if self.total > most: return error(
				Error("archive: limit exceeded", kind: "EOVERFLOW")
			)

fn var TarEntries.step(value: Bytes, var out: List[ArchiveEntry]) Unit!:
	if self.done: return ok(unit)

	self.buffer = self.buffer.concat(value)
	return self.drain(var out, false)

fn var TarEntries.finish(var out: List[ArchiveEntry]) Unit!:
	if self.done: return ok(unit)

	self.drain(var out, true)?
	if self.done or self.buffer.is_empty(): return ok(unit)

	return error(Error("archive: truncated tar", kind: "EBADMSG"))

// Reads the entries of a tar byte stream one at a time, for archives too big to hold in memory. Each entry is
// validated as `unpack` does; `max_entry_bytes` bounds one entry and `max_entries` and `max_bytes` the
// whole archive, failing the read with `EOVERFLOW`. A truncated archive fails with `EBADMSG`. Like `unpack` and
// `tar`, it stops at the first zero block and ignores what follows (archives are often padded to a blocking
// factor), and accepts a last member whose data is complete but whose padding is short; unlike compression
// streams, a tar has no trailer to check. Closing the result closes `input`.
export fn tar_entries(
	input: ReadStream[Bytes],
	options: ArchiveOptions = ArchiveOptions()
) ReadStream[ArchiveEntry]:
	var zeros = BytesBuilder()
	for index in 0..1024:
		zeros.append(0)
	return through[Bytes, ArchiveEntry](
		input,
		TarEntries(
			options: options, buffer: join([]), count: 0, total: 0, done: false,
			end: zeros.build(), names: Set[String](), files: Set[String](),
			parents: Set[String]()
		)
	)
