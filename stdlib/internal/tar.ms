import (
	Bytes, BytesBuilder, join from "@std/bytes.ms",
	min from "@std/math/math.ms",
)

/*
Tar reading and writing for `@std/io/archive.ms`: USTAR, GNU long names and PAX records are
read; writing emits USTAR headers when the path fits and PAX path records otherwise, with
deterministic metadata. Ported from the Rust `ms-std-archive` tar module, which followed
Go's `archive/tar`.
*/

export TAR_REG := 48
export TAR_DIR := 53
// What `TarReader.member` found.
export STEP_ITEM := 0
export STEP_END := 1
export STEP_BAD := 2

// The next member: its header fields and where its data section lies in the archive.
export type TarItem:
	status: Int
	name: Bytes
	typeflag: Int
	size: Int
	// Offset and length of the data bytes in the archive (empty for header-only types).
	start: Int
	length: Int
	// Declared data was not fully present.
	truncated: Bool

export type TarReader:
	data: Bytes
	pos: Int
	pad: Int

// Advances to the next member: a status of `STEP_END` is the end of the archive,
// `STEP_BAD` a malformed one.
fn var TarReader.member() TarItem:
	var pax = no_pax()
	var gnu_name = "".to_bytes()

	while true:
		if self.take(self.pad) < 0: return end_item()

		self.pad = 0

		head := self.read_header()
		if head.status == STEP_END: return end_item()
		if head.status == STEP_BAD: return bad_item()

		var name = head.name.clone()
		var typeflag = head.typeflag
		var size = head.size
		var nb = size
		if is_header_only(typeflag): nb = 0
		if nb < 0: return bad_item()

		self.pad = padding(nb)

		if typeflag == 120 or typeflag == 103:
			body := self.special(nb)
			if body.is_none(): return bad_item()

			records := parse_pax(body.get_or("".to_bytes()))
			if records.is_none(): return bad_item()

			found := records.get_or(no_pax())

			if typeflag == 103:
				merged := merge_pax(name, size, typeflag, found)
				if merged.is_none(): return bad_item()

				return TarItem(
					status: STEP_ITEM,
					name: merged.get_or(
						Merged(
							name: name.clone(),
							size: size,
							typeflag: typeflag,
						)
					).name.clone(),
					typeflag: 103,
					size: 0,
					start: self.pos,
					length: 0,
					truncated: false,
				)

			pax = found
			continue

		if typeflag == 76 or typeflag == 75:
			body := self.special(nb)
			if body.is_none(): return bad_item()

			if typeflag == 76: gnu_name = cstring(body.get_or("".to_bytes()))
			continue

		old_sparse := typeflag == 83

		if pax.present:
			merged := merge_pax(name, size, typeflag, pax)
			if merged.is_none(): return bad_item()

			m := merged.get_or(
				Merged(
					name: name.clone(),
					size: size,
					typeflag: typeflag,
				)
			)
			name = m.name.clone()
			size = m.size
			typeflag = m.typeflag

		if not gnu_name.is_empty():
			name = gnu_name.clone()
			gnu_name = "".to_bytes()

		if typeflag == 0:
			if name.length() > 0 and byte_at(name, name.length() - 1) == 47:
				typeflag = TAR_DIR
			else:
				typeflag = TAR_REG

		nb = size
		if is_header_only(typeflag): nb = 0
		if nb < 0: return bad_item()

		self.pad = padding(nb)
		if old_sparse and head.format != 4: return bad_item()

		available := self.data.length() - min(self.pos, self.data.length())
		start := self.pos
		truncated := available < nb
		var length = nb
		if truncated: length = available
		self.pos += length
		return TarItem(
			status: STEP_ITEM,
			name: name,
			typeflag: typeflag,
			size: size,
			start: start,
			length: length,
			truncated: truncated,
		)

	return bad_item()

// ---- reading ----

// Takes `n` bytes, returning their offset or -1 when fewer remain.
fn var TarReader.take(n: Int) Int:
	if n < 0 or self.pos + n > self.data.length(): return -1

	at := self.pos
	self.pos += n
	return at

fn var TarReader.read_header() Head:
	if self.pos >= self.data.length():
		return Head(
			status: STEP_END,
			name: "".to_bytes(),
			typeflag: 0,
			size: 0,
			format: 0,
		)

	at := self.take(BLOCK)
	if at < 0: return bad_head()

	block := sub(self.data, at, at + BLOCK)

	if all_zero(block):
		if self.pos >= self.data.length():
			return Head(
				status: STEP_END,
				name: "".to_bytes(),
				typeflag: 0,
				size: 0,
				format: 0,
			)

		second := self.take(BLOCK)
		if second < 0: return bad_head()
		if all_zero(self.data.view(second, second + BLOCK)):
			return Head(
				status: STEP_END,
				name: "".to_bytes(),
				typeflag: 0,
				size: 0,
				format: 0,
			)

		return bad_head()

	format := block_format(block)
	if format == 0: return bad_head()

	var name = cstring(block.view(0, 100))
	typeflag := byte_at(block, 156)
	size := numeric_field(block.view(124, 136))
	if size.is_none(): return bad_head()

	for range in [[100, 108], [108, 116], [116, 124], [136, 148]]:
		if not field_valid(block, range.get(0), range.get(1)): return bad_head()

	var prefix = "".to_bytes()

	if format != 1:
		if not field_valid(block, 329, 337) or not field_valid(block, 337, 345): return bad_head()

		if format == 2:
			prefix = cstring(block.view(345, 500))
		else if format == 3:
			prefix = cstring(block.view(345, 476))
			if not field_valid(block, 476, 488) or not field_valid(block, 488, 500): return bad_head()
		else if format == 4:
			if not (times_ok(block.view(345, 357)) and times_ok(block.view(357, 369))):
				// Pre-Go1.8 writers: the fields are really the USTAR prefix.
				p := cstring(block.view(345, 500))
				if is_ascii(p): prefix = p

	if not prefix.is_empty(): name = join([prefix, "/".to_bytes(), name])
	return Head(
		status: STEP_ITEM,
		name: name,
		typeflag: typeflag,
		size: size.get_or(0),
		format: format,
	)

// Reads a PAX or GNU special file of `size` bytes.
fn var TarReader.special(size: Int) Bytes?:
	if size < 0 or size > MAX_SPECIAL: return none

	at := self.take(size)
	if at < 0: return none

	return sub(self.data, at, at + size)

// Writes entries into one growing byte stream.
export type TarWriter:
	out: BytesBuilder
	written: Int

// Writes one entry; `directory` entries end in `/` and carry no data. Returns false for
// a file of 8 GiB or more.
fn var TarWriter.entry(name: Bytes, data: Bytes, directory: Bool) Bool:
	var mode = 384
	var flag = TAR_REG
	var size = data.length()

	if directory:
		mode = 448
		flag = TAR_DIR
		size = 0

	if size >= 8589934592: return false

	var block = new_block()
	split := split_ustar(name)

	if split.is_some() or (name.length() <= 100 and is_ascii(name)):
		parts := split.get_or(Split(prefix: "".to_bytes(), suffix: name.clone()))
		put_string(block, 0, 100, parts.suffix)
		put_string(block, 345, 500, parts.prefix)
	else:
		record := pax_record("path", name.clone())
		slash := rfind_byte(name, 47)
		var dir_part = "".to_bytes()
		var file_part = name.clone()

		if slash >= 0:
			dir_part = sub(name, 0, slash + 1)
			file_part = sub(name, slash + 1, name.length())

		var pax_name = to_ascii(
			clean_join(dir_part, "PaxHeaders.0".to_bytes(), file_part)
		)
		if pax_name.length() > 100: pax_name = sub(pax_name, 0, 100)
		while pax_name.length() > 0 and byte_at(pax_name, pax_name.length() - 1) == 47:
			pax_name = sub(pax_name, 0, pax_name.length() - 1)
		self.raw_pax(pax_name, record)
		put_string(block, 0, 100, to_ascii(name))

	octal(block, 100, 108, mode)
	octal(block, 108, 116, 0)
	octal(block, 116, 124, 0)
	octal(block, 124, 136, size)
	octal(block, 136, 148, 0)
	block[156] = flag
	octal(block, 329, 337, 0)
	octal(block, 337, 345, 0)
	put_string(block, 257, 263, "ustar\u{0}".to_bytes())
	put_string(block, 263, 265, "00".to_bytes())
	finish_block(block)
	self.emit(block_bytes(block))
	if not directory: self.emit(data)
	self.pad()
	return true

// Ends the archive with two zero blocks and returns it.
fn move TarWriter.finish() Bytes:
	self.out.append_bytes(zeros(1024))
	return self.out.build()

fn var TarWriter.emit(bytes: Bytes) Void:
	self.out.append_bytes(bytes)
	self.written += bytes.length()

fn var TarWriter.pad() Void:
	n := (512 - self.written % 512) % 512
	if n > 0: self.emit(zeros(n))

fn var TarWriter.raw_pax(name: Bytes, data: Bytes) Void:
	var block = new_block()
	put_string(block, 0, 100, name)
	octal(block, 100, 108, 0)
	octal(block, 108, 116, 0)
	octal(block, 116, 124, 0)
	octal(block, 124, 136, data.length())
	octal(block, 136, 148, 0)
	block[156] = 120
	put_string(block, 257, 263, "ustar\u{0}".to_bytes())
	put_string(block, 263, 265, "00".to_bytes())
	finish_block(block)
	self.emit(block_bytes(block))
	self.emit(data)
	self.pad()

export fn tar_reader(data: Bytes) TarReader:
	return TarReader(data: data.clone(), pos: 0, pad: 0)

export fn tar_writer() TarWriter:
	return TarWriter(out: BytesBuilder(), written: 0)

BLOCK := 512
MAX_SPECIAL := 1048576

// A header read from one block, with the format it was recognised as: 1 V7, 2 USTAR or
// PAX, 3 STAR, 4 GNU.
type Head:
	status: Int
	name: Bytes
	typeflag: Int
	size: Int
	format: Int

// A name and size once PAX records are applied.
type Merged:
	name: Bytes
	size: Int
	typeflag: Int

// The PAX records that matter, last occurrence of a key winning.
type Pax:
	present: Bool
	sparse: Bool
	path: Bytes?
	uid: Bytes?
	gid: Bytes?
	atime: Bytes?
	mtime: Bytes?
	ctime: Bytes?
	size: Bytes?

type Split:
	prefix: Bytes
	suffix: Bytes

fn end_item() TarItem:
	return TarItem(
		status: STEP_END,
		name: "".to_bytes(),
		typeflag: 0,
		size: 0,
		start: 0,
		length: 0,
		truncated: false,
	)

fn bad_item() TarItem:
	return TarItem(
		status: STEP_BAD,
		name: "".to_bytes(),
		typeflag: 0,
		size: 0,
		start: 0,
		length: 0,
		truncated: false,
	)

fn no_pax() Pax:
	return Pax(
		present: false,
		sparse: false,
		path: none,
		uid: none,
		gid: none,
		atime: none,
		mtime: none,
		ctime: none,
		size: none,
	)

fn bad_head() Head:
	return Head(status: STEP_BAD, name: "".to_bytes(), typeflag: 0, size: 0, format: 0)

fn byte_at(b: Bytes, i: Int) Int:
	return b.get(i).to_int()

fn sub(b: Bytes, start: Int, end: Int) Bytes:
	return b.view(start, end).clone()

fn rfind_byte(s: Bytes, c: Int) Int:
	var i = s.length() - 1

	while i >= 0:
		if byte_at(s, i) == c: return i

		i -= 1

	return -1

fn zeros(n: Int) Bytes:
	var out = BytesBuilder()
	for i in 0..n: out.append(0)
	return out.build()

fn is_header_only(flag: Int) Bool:
	return flag >= 49 and flag <= 54

fn padding(n: Int) Int:
	return (512 - n % 512) % 512

fn is_ascii(s: Bytes) Bool:
	for i in 0..s.length():
		c := byte_at(s, i)
		if c >= 128 or c == 0: return false

	return true

// The bytes before the first NUL.
fn cstring(b: Bytes) Bytes:
	for i in 0..b.length():
		if byte_at(b, i) == 0: return sub(b, 0, i)
	return b.clone()

// Parses an octal field. A value of 2^63 or more reads as -1 (a negative size, which
// every caller rejects); malformed text is none.
fn octal_field(b: Bytes) Int?:
	var start = 0
	var end = b.length()
	while start < end and (byte_at(b, start) == 32 or byte_at(b, start) == 0): start += 1
	while end > start and (byte_at(b, end - 1) == 32 or byte_at(b, end - 1) == 0): end -= 1
	if start == end: return 0

	s := cstring(sub(b, start, end))
	if s.is_empty(): return none

	var x = 0
	var digits = 0
	var first = 0

	for i in 0..s.length():
		c := byte_at(s, i)
		if c < 48 or c > 55: return none

		d := c - 48
		if digits == 0 and d == 0: continue

		digits += 1
		if digits == 1: first = d
		if digits > 22: return none

		if digits <= 21: x = x * 8 + d

	if digits == 22:
		if first > 1: return none
		return -1

	return x

// Parses an octal field or a base-256 number.
fn numeric_field(b: Bytes) Int?:
	if b.length() > 0 and byte_at(b, 0) >= 128:
		var inverted = false
		if (byte_at(b, 0) / 64) % 2 == 1: inverted = true

		var x = 0

		for i in 0..b.length():
			var c = byte_at(b, i)
			if inverted: c = 255 - c
			if i == 0: c %= 128
			if x >= 36028797018963968: return none

			x = x * 256 + c

		if inverted: return -x - 1

		return x

	return octal_field(b)

fn checksum(block: Bytes) Int:
	var unsigned = 0

	for i in 0..512:
		var c = byte_at(block, i)
		if i >= 148 and i < 156: c = 32
		unsigned += c

	return unsigned

fn signed_checksum(block: Bytes) Int:
	var signed = 0

	for i in 0..512:
		var c = byte_at(block, i)
		if i >= 148 and i < 156: c = 32
		if c >= 128: c -= 256
		signed += c

	return signed

// The format of a header block, or 0 for none.
fn block_format(block: Bytes) Int:
	value := octal_field(block.view(148, 156))
	if value.is_none(): return 0

	v := value.get_or(0)
	if v != checksum(block) and v != signed_checksum(block): return 0

	magic := block.view(257, 263)
	version := block.view(263, 265)
	trailer := block.view(508, 512)
	ustar := "ustar\u{0}".view_bytes()
	if magic == ustar and trailer == "tar\u{0}".view_bytes(): return 3
	if magic == ustar: return 2
	if magic == "ustar ".view_bytes() and version == " \u{0}".view_bytes(): return 4

	return 1

fn parse_dec(s: Bytes) Int?:
	text := s.decode_utf8()?
	var digits = text.clone()

	if digits.starts_with("+"):
		digits = digits.slice(1, digits.length())
		if digits.starts_with("-") or digits.starts_with("+"): return none

	return digits.parse_int()

fn all_zero(block: Bytes) Bool:
	for i in 0..block.length():
		if byte_at(block, i) != 0: return false
	return true

fn field_valid(block: Bytes, start: Int, end: Int) Bool:
	return numeric_field(block.view(start, end)).is_some()

fn times_ok(field: Bytes) Bool:
	return byte_at(field, 0) == 0 or numeric_field(field).is_some()

fn parse_pax(s: Bytes) Pax?:
	var out = no_pax()
	out.present = true

	var pos = 0
	var sparse_offsets = 0

	while pos < s.length():
		space := s.index_of_byte(32, pos)
		if space.is_none(): return none

		sp := space.get_or(0)
		n := parse_dec(sub(s, pos, sp))?
		if n < 5 or n > s.length() - pos: return none

		count := n - (sp - pos + 1)
		if count <= 0: return none

		rest := sp + 1
		if byte_at(s, rest + count - 1) != 10: return none

		record := sub(s, rest, rest + count - 1)
		equals := record.index_of_byte(61, 0)
		if equals.is_none(): return none

		eq := equals.get_or(0)
		key := sub(record, 0, eq)
		value := sub(record, eq + 1, record.length())
		if key.is_empty(): return none

		key_text := key.decode_utf8()
		var is_listed = key == "path".to_bytes() or key == "linkpath".to_bytes()
		if not is_listed:
			is_listed = key == "uname".to_bytes() or key == "gname".to_bytes()

		if is_listed:
			if value.contains(zeros(1)): return none
		else:
			if key.contains(zeros(1)): return none

		pos = rest + count

		if (
			key == "GNU.sparse.offset".to_bytes()
			or key == "GNU.sparse.numbytes".to_bytes()
		):
			want_offset := sparse_offsets % 2 == 0
			if want_offset and key != "GNU.sparse.offset".to_bytes(): return none
			if not want_offset and key != "GNU.sparse.numbytes".to_bytes(): return none
			if value.contains(",".to_bytes()): return none

			sparse_offsets += 1
			out.sparse = true
		else if key_text.is_some():
			name := key_text.get_or("")
			if name == "path": out.path = value.clone()
			if name == "uid": out.uid = value.clone()
			if name == "gid": out.gid = value.clone()
			if name == "atime": out.atime = value.clone()
			if name == "mtime": out.mtime = value.clone()
			if name == "ctime": out.ctime = value.clone()
			if name == "size": out.size = value.clone()
			if name.starts_with("GNU.sparse."): out.sparse = true

	return out

fn parse_pax_time(s: Bytes) Bool:
	dot := s.index_of_byte(46, 0)
	var seconds = s.clone()
	var fraction = "".to_bytes()

	if dot.is_some():
		seconds = sub(s, 0, dot.get_or(0))
		fraction = sub(s, dot.get_or(0) + 1, s.length())

	if parse_dec(seconds).is_none(): return false

	for i in 0..fraction.length():
		c := byte_at(fraction, i)
		if c < 48 or c > 57: return false

	return true

// Applies PAX records to a header's name and size; none when a record is malformed.
fn merge_pax(name: Bytes, size: Int, typeflag: Int, pax: Pax) Merged?:
	var merged_name = name.clone()
	var merged_size = size
	var merged_flag = typeflag
	if path := pax.path:
		if not path.is_empty(): merged_name = path.clone()
	for value in [pax.uid, pax.gid]:
		if v := value:
			if not v.is_empty() and parse_dec(v).is_none(): return none
	for value in [pax.atime, pax.mtime, pax.ctime]:
		if v := value:
			if not v.is_empty() and not parse_pax_time(v): return none

	if value := pax.size:
		if not value.is_empty():
			parsed := parse_dec(value)?
			merged_size = parsed

	if pax.sparse:
		// Sparse members are expanded by Go; treat them as unsupported typeflags
		// instead.
		merged_flag = 83
	return Merged(name: merged_name, size: merged_size, typeflag: merged_flag)

// ---- writing ----

fn new_block() List[Int]:
	var block: List[Int] = []
	for i in 0..BLOCK: block.append(0)
	return block

fn block_bytes(block: List[Int]) Bytes:
	var out = BytesBuilder()
	for b in block: out.append(b.to_uint8().get_or(0))
	return out.build()

fn put_string(var block: List[Int], from: Int, to: Int, s: Bytes) Void:
	width := to - from
	n := min(s.length(), width)
	for i in 0..n: block[from + i] = byte_at(s, i)
	if s.length() < width: block[from + s.length()] = 0

	if s.length() > width and block[to - 1] == 47:
		var end = width - 1
		while end > 0 and byte_at(s, end - 1) == 47: end -= 1
		block[from + end] = 0

// Writes `x` as zero-padded octal ending in a NUL.
fn octal(var block: List[Int], from: Int, to: Int, x: Int) Void:
	var digits: List[Int] = []
	var rest = x

	while rest > 0:
		digits.append(48 + rest % 8)
		rest /= 8

	width := to - from - 1
	var text = BytesBuilder()
	for i in digits.length()..width: text.append(48)

	var i = digits.length() - 1

	while i >= 0:
		text.append(digits.get(i).to_uint8().get_or(0))
		i -= 1

	put_string(block, from, to, text.build())

fn finish_block(var block: List[Int]) Void:
	for i in 148..156: block[i] = 32

	sum := checksum(block_bytes(block))
	octal(block, 148, 155, sum)
	block[155] = 32

// Splits a long path at a slash into a USTAR prefix and name, or none.
fn split_ustar(name: Bytes) Split?:
	var length = name.length()
	if length <= 100 or not is_ascii(name): return none

	if length > 156:
		length = 156
	else if byte_at(name, length - 1) == 47:
		length -= 1

	i := rfind_byte(sub(name, 0, length), 47)
	if i < 0: return none

	suffix_length := name.length() - i - 1
	if i == 0 or suffix_length > 100 or suffix_length == 0 or i > 155: return none

	return Split(prefix: sub(name, 0, i), suffix: sub(name, i + 1, name.length()))

fn pax_record(key: String, value: Bytes) Bytes:
	base := key.length() + value.length() + 3
	var size = base + f"{base}".length()
	var record = join([f"{size} {key}=".to_bytes(), value.clone(), "\n".to_bytes()])

	if record.length() != size:
		size = record.length()
		record = join([f"{size} {key}=".to_bytes(), value.clone(), "\n".to_bytes()])

	return record

// path.Join(dir, mid, file) for already-clean components.
fn clean_join(dir: Bytes, mid: Bytes, file: Bytes) Bytes:
	var parts: List[Bytes] = []
	var rooted = false
	if dir.length() > 0 and byte_at(dir, 0) == 47: rooted = true

	for piece in [dir, mid, file]:
		for segment in piece.split("/".to_bytes()):
			if segment.is_empty() or segment == ".".to_bytes(): continue

			if segment == "..".to_bytes():
				last := parts.last()

				if last.is_some() and last.get_or("".to_bytes()) != "..".to_bytes():
					parts.pop()
				else if not rooted:
					parts.append(segment.clone())
			else:
				parts.append(segment.clone())

	return join(parts_with_slashes(parts))

fn parts_with_slashes(parts: List[Bytes]) List[Bytes]:
	var out: List[Bytes] = []

	for i in 0..parts.length():
		if i > 0: out.append("/".to_bytes())
		out.append(parts.get(i).clone())

	return out

fn to_ascii(s: Bytes) Bytes:
	var out = BytesBuilder()

	for i in 0..s.length():
		c := byte_at(s, i)
		if c < 128 and c != 0: out.append(s.get(i))

	return out.build()
