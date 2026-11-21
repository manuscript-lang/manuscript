import (
	Bytes, BytesBuilder, join from "@std/bytes.ms",
	crc32 from "@std/data/checksum.ms",
	min from "@std/math/math.ms",

	msstd_compress_compress, msstd_compress_decompress from "@std/internal/archive.ms",
)

/*
Zip reading and writing for `@std/io/archive.ms`: end-of-central-directory search (with
prefix data and zip64), stored and deflated members, data descriptors and CRC
verification. Ported from the Rust `ms-std-archive` zip module, which followed Go's
`archive/zip`. Integers wider than 63 bits clamp to the largest `Int`.
*/

// A member from the central directory.
export type ZipFile:
	name: Bytes
	creator: Int
	flags: Int
	method: Int
	crc: Int
	compressed_size: Int
	size: Int
	attrs: Int
	offset: Int

// Whether the member is a regular file and whether it is a directory, as Go's
// `FileHeader.Mode` decides.
fn ZipFile.is_directory() Bool:
	var directory = false
	creator := self.creator / 256

	if creator == 3 or creator == 19:
		mode := (self.attrs / 65536) % 65536
		kind := mode - mode % 4096
		if kind == 16384: directory = true
	else if creator == 11 or creator == 14 or creator == 0:
		directory = (self.attrs / 16) % 2 == 1

	if self.name.length() > 0 and self.name.get(self.name.length() - 1).to_int() == 47: directory = true
	return directory

fn ZipFile.is_irregular() Bool:
	creator := self.creator / 256

	if creator == 3 or creator == 19:
		mode := (self.attrs / 65536) % 65536
		kind := mode - mode % 4096
		return (
			kind == 24576
			or kind == 8192
			or kind == 4096
			or kind == 40960
			or kind == 49152
		)

	return false

fn ZipFile.body_offset(data: Bytes) Int:
	if self.offset < 0 or self.offset + 30 > data.length(): return -1
	if u32le(data, self.offset) != 67324752: return -1

	return (
		self.offset
		+ 30
		+ u16le(data, self.offset + 26)
		+ u16le(data, self.offset + 28)
	)

// A member to write: its name (directories end in `/`), data and kind.
export type ZipMember:
	name: Bytes
	data: Bytes
	directory: Bool

// The central directory of an archive held in memory, in directory order; none when the
// archive is malformed.
export fn zip_open(data: Bytes) List[ZipFile]?:
	end_at := find_end(data)?
	length := data.length()
	var records = u16le(data, end_at + 10)
	var directory_size = u32le(data, end_at + 12)
	var directory_offset = u32le(data, end_at + 16)
	var end_offset = end_at

	if (
		records == 65535
		or directory_size == 4294967295
		or directory_offset == 4294967295
	):
		loc := end_offset - DIR64_LOC_LEN

		if loc >= 0:
			if (
				u32le(data, loc) == DIR64_LOC_SIG
				and u32le(data, loc + 4) == 0
				and u32le(data, loc + 16) == 1
			):
				p := u64le(data, loc + 8)
				if p < 0: return none

				end_offset = p
				if p + DIR64_END_LEN > length: return none
				if u32le(data, p) != DIR64_END_SIG: return none

				records = u64le(data, p + 32)
				directory_size = u64le(data, p + 40)
				directory_offset = u64le(data, p + 48)

	if directory_size < 0 or directory_offset < 0: return none

	var base = end_offset - directory_size - directory_offset
	o := base + directory_offset
	if o < 0 or o >= length: return none

	if base > 0 and directory_offset <= length:
		probe := read_dir_header(data, directory_offset)
		if probe.status == 0: base = 0

	start := base + directory_offset
	if start < 0 or start > length: return none

	var files: List[ZipFile] = []
	var pos = start

	while true:
		step := read_dir_header(data, pos)
		if step.status == 1: return none
		if step.status != 0: break

		var file = step.file.clone()
		file.offset += base
		files.append(file)
		pos = step.next

	if files.length() % 65536 != records % 65536: return none

	return files

// Whether the member is neither a regular file nor a directory.
export fn zip_unsupported(file: ZipFile) Bool:
	return not file.is_directory() and file.is_irregular()

export fn zip_is_directory(file: ZipFile) Bool:
	return file.is_directory()

export fn zip_name_is_utf8(file: ZipFile) Bool:
	return file.name.decode_utf8().is_some()

// The failures of Go's `File.Open`: a bad local header or an unsupported method.
export fn zip_check_open(file: ZipFile, data: Bytes) Bool:
	if file.body_offset(data) < 0: return false
	if not ends_with_slash(file.name) and file.method != 0 and file.method != 8: return false

	return true

// Fully verifies and returns the member body; none when it is damaged.
export fn zip_read(file: ZipFile, data: Bytes) Bytes?:
	body := file.body_offset(data)
	if body < 0: return none

	if ends_with_slash(file.name):
		if file.size == 0: return "".to_bytes()
		return none

	// A body running past the file is simply short.
	available := max_zero(data.length() - body)
	stored_length := min(available, file.compressed_size)
	from := min(body, data.length())
	stored := data.view(from, from + stored_length)
	var out = "".to_bytes()

	if file.method == 0:
		if stored.length() != file.compressed_size or file.compressed_size > file.size: return none

		out = stored.clone()
	else:
		room := min(file.size, 9223372036854775806)
		inflated := msstd_compress_decompress(stored.clone(), "deflate", room)
		if inflated.is_error(): return none

		out = inflated.get_or("".to_bytes())

	if out.length() != file.size: return none

	sum := crc32(out).to_int()

	if (file.flags / 8) % 2 == 1:
		at := body + file.compressed_size
		if file.compressed_size < 0 or at < 0: return none

		var d = "".to_bytes()
		if at < data.length(): d = data.slice(at, min(data.length(), at + 16)).get_or(
			"".to_bytes()
		)

		// A leading signature is optional; either way the CRC is followed by two sizes.
		var crc_at = 0
		var need = 12

		if d.length() >= 4 and u32le(d, 0) == DATA_DESC_SIG:
			crc_at = 4
			need = 16

		if d.length() < need or u32le(d, crc_at) != file.crc or sum != file.crc: return none
	else if sum != file.crc:
		return none

	return out

// Writes the members with deflate at `level` and returns the archive.
export fn zip_pack(members: List[ZipMember], level: Int) Bytes:
	var w = ZipOut(out: BytesBuilder(), length: 0)
	var records: List[ZipRecord] = []
	var extra = ZipOut(out: BytesBuilder(), length: 0)
	extra.le(21589, 2)
	extra.le(5, 2)
	extra.le(1, 1)
	extra.le(315532800, 4)

	extra_bytes := extra.out.build()

	for member in members:
		var flags = 0
		if needs_utf8_flag(member.name): flags = 2048

		offset := w.length
		var method = 0
		var body = "".to_bytes()
		var crc = 0
		var size = 0

		if not member.directory:
			flags += 8
			if member.data.length() >= 64: method = 8

			if method == 8:
				body = deflate(member.data, level)
			else:
				body = member.data.clone()

			crc = crc32(member.data).to_int()
			size = member.data.length()

		csize := body.length()
		zip64 := csize >= 4294967295 or size >= 4294967295
		var version = 20
		if zip64: version = 45
		w.le(67324752, 4)
		w.le(version, 2)
		w.le(flags, 2)
		w.le(method, 2)
		w.le(0, 2)
		w.le(33, 2)
		w.zeros(12)
		w.le(member.name.length(), 2)
		w.le(extra_bytes.length(), 2)
		w.put(member.name)
		w.put(extra_bytes)
		w.put(body)

		if not member.directory:
			w.le(134695760, 4)
			w.le(crc, 4)

			if zip64:
				w.le(csize, 8)
				w.le(size, 8)
			else:
				w.le(csize, 4)
				w.le(size, 4)

		var attrs = 0x8180 * 65536
		if member.directory: attrs = 0x41c0 * 65536 + 16
		records.append(
			ZipRecord(
				flags: flags,
				method: method,
				crc: crc,
				attrs: attrs,
				offset: offset,
				zip64: zip64,
				compressed_size: csize,
				size: size,
			)
		)

	start := w.length

	for i in 0..members.length():
		member := members.get(i)
		record := records.get(i)
		big := record.zip64 or record.offset >= 4294967295
		var extra_field = extra_bytes.clone()

		if big:
			var more = ZipOut(out: BytesBuilder(), length: 0)
			more.put(extra_bytes)
			more.le(1, 2)
			more.le(24, 2)
			more.le(record.size, 8)
			more.le(record.compressed_size, 8)
			more.le(record.offset, 8)
			extra_field = more.out.build()

		var version = 20
		if record.zip64: version = 45
		w.le(33639248, 4)
		w.le(788, 2)
		w.le(version, 2)
		w.le(record.flags, 2)
		w.le(record.method, 2)
		w.le(0, 2)
		w.le(33, 2)
		w.le(record.crc, 4)

		if big:
			w.le(4294967295, 4)
			w.le(4294967295, 4)
		else:
			w.le(record.compressed_size, 4)
			w.le(record.size, 4)

		w.le(member.name.length(), 2)
		w.le(extra_field.length(), 2)
		w.le(0, 2)
		w.zeros(4)
		w.le(record.attrs, 4)

		if record.offset > 4294967295:
			w.le(4294967295, 4)
		else:
			w.le(record.offset, 4)

		w.put(member.name)
		w.put(extra_field)

	end := w.length
	var count = members.length()
	var directory_size = end - start
	var directory_offset = start

	if count >= 65535 or directory_size >= 4294967295 or directory_offset >= 4294967295:
		w.le(101075792, 4)
		w.le(44, 8)
		w.le(45, 2)
		w.le(45, 2)
		w.le(0, 4)
		w.le(0, 4)
		w.le(count, 8)
		w.le(count, 8)
		w.le(directory_size, 8)
		w.le(directory_offset, 8)
		w.le(117853008, 4)
		w.le(0, 4)
		w.le(end, 8)
		w.le(1, 4)
		count = 65535
		directory_size = 4294967295
		directory_offset = 4294967295

	w.le(101010256, 4)
	w.zeros(4)
	w.le(count, 2)
	w.le(count, 2)
	w.le(directory_size, 4)
	w.le(directory_offset, 4)
	w.le(0, 2)
	return w.out.build()

DIR_HEADER_SIG := 33639248
DIR64_END_SIG := 101075792
DIR64_LOC_SIG := 117853008
DATA_DESC_SIG := 134695760
DIR_HEADER_LEN := 46
DIR_END_LEN := 22
DIR64_END_LEN := 56
DIR64_LOC_LEN := 20

// One central-directory record read, or why none was: status 0 read, 1 no bytes left
// (a hard error), 2 truncated, 3 malformed.
type DirStep:
	status: Int
	file: ZipFile
	next: Int

// What a member writes into the central directory.
type ZipRecord:
	flags: Int
	method: Int
	crc: Int
	attrs: Int
	offset: Int
	zip64: Bool
	compressed_size: Int
	size: Int

type ZipOut:
	out: BytesBuilder
	length: Int

fn var ZipOut.put(bytes: Bytes) Void:
	self.out.append_bytes(bytes)
	self.length += bytes.length()

fn var ZipOut.zeros(n: Int) Void:
	for i in 0..n: self.out.append(0)
	self.length += n

// Appends `x` in little-endian order over `width` bytes.
fn var ZipOut.le(x: Int, width: Int) Void:
	var rest = x

	for i in 0..width:
		self.out.append((rest % 256).to_uint8().get_or(0))
		rest /= 256

	self.length += width

fn max_zero(x: Int) Int:
	if x < 0: return 0
	return x

fn ends_with_slash(name: Bytes) Bool:
	return name.length() > 0 and name.get(name.length() - 1).to_int() == 47

fn u16le(b: Bytes, at: Int) Int:
	return b.get(at).to_int() + b.get(at + 1).to_int() * 256

fn u32le(b: Bytes, at: Int) Int:
	return u16le(b, at) + u16le(b, at + 2) * 65536

// A 64-bit field; values of 2^63 or more clamp to the largest `Int`.
fn u64le(b: Bytes, at: Int) Int:
	return b.int64_le(at).get_or(9223372036854775807)

fn deflate(data: Bytes, level: Int) Bytes:
	return msstd_compress_compress(data, "deflate", level, none).get_or("".to_bytes())

// The offset of the end-of-central-directory record, or none.
fn find_end(data: Bytes) Int?:
	size := data.length()
	var round = 0

	for limit in [1024, 66560]:
		length := min(limit, size)
		start := size - length
		var found = -1

		if length >= DIR_END_LEN:
			var at = length - DIR_END_LEN

			while at >= 0:
				if (
					data.get(start + at).to_int() == 80
					and data.get(start + at + 1).to_int() == 75
					and data.get(start + at + 2).to_int() == 5
					and data.get(start + at + 3).to_int() == 6
				):
					found = at
					break

				at -= 1

		last := round == 1 or length == size

		if found >= 0:
			comment := u16le(data, start + found + 20)

			if comment + DIR_END_LEN + found > length:
				// Go returns "not found" for this block rather than scanning on.
				if last: return none
			else:
				return start + found
		else if last:
			return none

		round += 1

	return none

fn clamp_u64(x: Int) Int:
	return x

fn read_dir_header(data: Bytes, at: Int) DirStep:
	length := data.length()
	empty := ZipFile(
		name: "".to_bytes(),
		creator: 0,
		flags: 0,
		method: 0,
		crc: 0,
		compressed_size: 0,
		size: 0,
		attrs: 0,
		offset: 0,
	)
	if at >= length: return DirStep(status: 1, file: empty.clone(), next: length)
	if length - at < DIR_HEADER_LEN: return DirStep(
		status: 2,
		file: empty.clone(),
		next: length,
	)
	if u32le(data, at) != DIR_HEADER_SIG: return DirStep(
		status: 3,
		file: empty.clone(),
		next: at + 4,
	)

	name_length := u16le(data, at + 28)
	extra_length := u16le(data, at + 30)
	comment_length := u16le(data, at + 32)
	var file = ZipFile(
		name: "".to_bytes(),
		creator: u16le(data, at + 4),
		flags: u16le(data, at + 8),
		method: u16le(data, at + 10),
		crc: u32le(data, at + 16),
		compressed_size: u32le(data, at + 20),
		size: u32le(data, at + 24),
		attrs: u32le(data, at + 38),
		offset: u32le(data, at + 42),
	)
	c32 := u32le(data, at + 20)
	u32v := u32le(data, at + 24)
	off32 := u32le(data, at + 42)
	total := name_length + extra_length + comment_length
	rest := at + DIR_HEADER_LEN

	if length - rest < total:
		eof := rest >= length and total > 0
		var status = 2
		if eof: status = 1
		return DirStep(status: status, file: empty.clone(), next: length)

	file.name = data.view(rest, rest + name_length).clone()

	extra_start := rest + name_length
	next := rest + total
	var need_size = u32v == 4294967295
	var need_compressed = c32 == 4294967295
	var need_offset = off32 == 4294967295
	var e = extra_start
	extra_end := extra_start + extra_length

	while extra_end - e >= 4:
		tag := u16le(data, e)
		field_size := u16le(data, e + 2)
		e += 4
		if extra_end - e < field_size: break

		var field = e
		e += field_size

		field_end := field + field_size

		if tag == 1:
			if need_size:
				need_size = false
				if field_end - field < 8: return DirStep(
					status: 3,
					file: empty.clone(),
					next: next,
				)

				file.size = u64le(data, field)
				field += 8

			if need_compressed:
				need_compressed = false
				if field_end - field < 8: return DirStep(
					status: 3,
					file: empty.clone(),
					next: next,
				)

				file.compressed_size = u64le(data, field)
				field += 8

			if need_offset:
				need_offset = false
				if field_end - field < 8: return DirStep(
					status: 3,
					file: empty.clone(),
					next: next,
				)

				file.offset = data.int64_le(field).get_or(0)
				field += 8

	if need_compressed or need_offset: return DirStep(
		status: 3,
		file: empty.clone(),
		next: next,
	)

	return DirStep(status: 0, file: file, next: next)

fn needs_utf8_flag(name: Bytes) Bool:
	if name.decode_utf8().is_none(): return false

	for i in 0..name.length():
		c := name.get(i).to_int()
		if c < 32 or c > 125 or c == 92: return true

	return false
