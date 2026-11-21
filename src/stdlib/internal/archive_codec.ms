import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	ArchiveEntry, ArchiveFormat from "@std/io/archive.ms",
	min from "@std/math/math.ms",

	ArchiveLimits from "@std/internal/archive.ms",
	STEP_BAD,
	STEP_END,
	TAR_DIR,
	TAR_REG,
	tar_reader,
	tar_writer from "@std/internal/tar.ms",
	ZipFile,
	ZipMember,
	zip_check_open,
	zip_is_directory,
	zip_name_is_utf8,
	zip_open,
	zip_pack,
	zip_read,
	zip_unsupported from "@std/internal/zip.ms",
)

/*
In-memory `pack` and `unpack` for `@std/io/archive.ms`: the path rules, duplicate and
file-versus-directory conflicts, and the entry and size limits, over the tar and zip
codecs. Failures carry the kinds `EINVAL` (bad input), `EBADMSG` (bad archive), `EOVERFLOW`
(limit) and `ENOTSUP` (member type).
*/

// Encodes `entries` as `format`; `max_bytes` bounds the encoded size.
export fn pack_entries(
	entries: List[ArchiveEntry],
	format: ArchiveFormat,
	max_bytes: Int?,
) Bytes!:
	max := budget(max_bytes)
	if max < 0: return error(Error("archive: invalid input", kind: "EINVAL"))

	var seen = Set[String]()
	var kinds = Map[String, Bool]()

	for entry in entries:
		if not path_valid(entry.path.to_bytes(), entry.directory):
			return error(Error("archive: invalid input", kind: "EINVAL"))
		if entry.directory and entry.data.length() > 0:
			return error(Error("archive: invalid input", kind: "EINVAL"))

		key := clean(entry.path, entry.directory)
		if seen.contains(key.clone()):
			return error(Error("archive: invalid data", kind: "EBADMSG"))

		seen.add(key.clone())
		kinds.add(key, entry.directory)

	if has_conflict(kinds): return error(
		Error("archive: invalid data", kind: "EBADMSG")
	)

	var out = "".to_bytes()

	match format:
		Zip:
			var members: List[ZipMember] = []

			for entry in entries:
				var name = clean(entry.path, entry.directory).to_bytes()
				if entry.directory: name = join_slash(name)
				if name.length() > 65535: return error(
					Error("archive: invalid input", kind: "EINVAL")
				)

				members.append(
					ZipMember(
						name: name,
						data: entry.data.clone(),
						directory: entry.directory,
					)
				)

			out = zip_pack(members, 5)
		Tar:
			var writer = tar_writer()

			for entry in entries:
				var name = clean(entry.path, entry.directory).to_bytes()
				if entry.directory: name = join_slash(name)
				if not writer.entry(name, entry.data, entry.directory):
					return error(Error("archive: limit exceeded", kind: "EOVERFLOW"))
				if writer.written > max: return error(
					Error(
						"archive: limit exceeded",
						kind: "EOVERFLOW",
					)
				)

			out = writer.finish()

	if out.length() > max: return error(
		Error("archive: limit exceeded", kind: "EOVERFLOW")
	)

	return ok(out)

// Decodes `data` as `format` under `limits`.
export fn unpack_entries(
	data: Bytes,
	format: ArchiveFormat,
	limits: ArchiveLimits,
) List[ArchiveEntry]!:
	count := budget(limits.max_entries)
	entry_max := budget(limits.max_entry_bytes)
	total := budget(limits.max_total_bytes)
	if count < 0 or entry_max < 0 or total < 0:
		return error(Error("archive: invalid input", kind: "EINVAL"))

	var c = Collector(
		out: [],
		seen: Set[String](),
		kinds: Map[String, Bool](),
		count: count,
		entry_max: entry_max,
		total: total,
	)

	match format:
		Tar: c.read_tar(data)?
		Zip: c.read_zip(data)?

	if has_conflict(c.kinds): return error(
		Error("archive: invalid data", kind: "EBADMSG")
	)

	return ok(c.out.clone())

type Collector:
	out: List[ArchiveEntry]
	seen: Set[String]
	kinds: Map[String, Bool]
	count: Int
	entry_max: Int
	total: Int

fn var Collector.read_tar(data: Bytes) Void!:
	var reader = tar_reader(data)

	while true:
		item := reader.member()
		if item.status == STEP_BAD: return error(
			Error("archive: invalid data", kind: "EBADMSG")
		)
		if item.status == STEP_END: break

		flag := item.typeflag
		if flag != TAR_REG and flag != 0 and flag != TAR_DIR:
			return error(Error("archive: unsupported", kind: "ENOTSUP"))

		directory := flag == TAR_DIR

		// `tar -cf x.tar .` prefixes every member with `./` and adds a bare `./` entry.
		var name = item.name.clone()
		while name.starts_with("./".to_bytes()):
			name = name.view(2, name.length()).clone()
		if directory and (name.length() == 0 or name.equals(".".to_bytes())): continue

		self.admit(name, directory, item.size)?
		if item.truncated: return error(Error("archive: invalid data", kind: "EBADMSG"))

		self.push(
			name,
			data.view(item.start, item.start + item.length).clone(),
			directory,
		)?

fn var Collector.read_zip(data: Bytes) Void!:
	files := zip_open(data)
	if files.is_none(): return error(Error("archive: invalid data", kind: "EBADMSG"))

	list := files.get()
	if list.length() > self.count: return error(
		Error("archive: limit exceeded", kind: "EOVERFLOW")
	)

	for file in list:
		directory := zip_is_directory(file)
		if not zip_name_is_utf8(file) or zip_unsupported(file):
			return error(Error("archive: unsupported", kind: "ENOTSUP"))
		if file.size > self.entry_max or file.size > self.total:
			return error(Error("archive: limit exceeded", kind: "EOVERFLOW"))

		// Go opens the member (header and algorithm checks) before validating its path.
		if not zip_check_open(file, data): return error(
			Error("archive: invalid data", kind: "EBADMSG")
		)

		self.admit(file.name, directory, file.size)?

		body := zip_read(file, data)
		if body.is_none(): return error(Error("archive: invalid data", kind: "EBADMSG"))

		self.push(file.name, body.get(), directory)?

// Go's `add` closure, before the body is read: the path must be valid and new, and the
// declared size and count within the limits.
fn var Collector.admit(name: Bytes, directory: Bool, size: Int) Void!:
	if not path_valid(name, directory): return error(
		Error("archive: invalid data", kind: "EBADMSG")
	)

	key := clean(name.decode_utf8().get_or(""), directory)
	if self.seen.contains(key.clone()): return error(
		Error("archive: invalid data", kind: "EBADMSG")
	)

	self.seen.add(key.clone())
	self.kinds.add(key, directory)
	if self.out.length() >= self.count or size > self.entry_max or size > self.total:
		return error(Error("archive: limit exceeded", kind: "EOVERFLOW"))

// The rest of `add`: the verified body against the limits, then the entry.
fn var Collector.push(name: Bytes, body: Bytes, directory: Bool) Void!:
	if body.length() > min(self.entry_max, self.total):
		return error(Error("archive: limit exceeded", kind: "EOVERFLOW"))
	if directory and body.length() > 0: return error(
		Error("archive: invalid data", kind: "EBADMSG")
	)

	self.total -= body.length()

	path := name.decode_utf8()
	if path.is_none(): return error(Error("archive: invalid data", kind: "EBADMSG"))

	self.out.append(ArchiveEntry(clean(path.get(), directory), body, directory))

// The limit as a size: no limit is the largest `Int`, a negative one is -1.
fn budget(limit: Int?) Int:
	if limit.is_none(): return 9223372036854775807
	if limit.get() < 0: return -1

	return limit.get()

// Valid paths are non-empty UTF-8 without backslashes, colons or NULs, relative, with
// no empty, `.` or `..` segment; a directory may end in one `/`.
fn path_valid(s: Bytes, directory: Bool) Bool:
	if s.length() == 0 or s.decode_utf8().is_none(): return false

	for i in 0..s.length():
		c := s.get(i).to_int()
		if c == 92 or c == 58 or c == 0: return false

	if s.get(0).to_int() == 47: return false

	var end = s.length()
	last := s.get(end - 1).to_int()

	if directory:
		if last == 47: end -= 1
	else if last == 47:
		return false

	var start = 0

	for i in 0..end + 1:
		if i == end or s.get(i).to_int() == 47:
			len := i - start
			if len == 0: return false
			if len == 1 and s.get(start).to_int() == 46: return false
			if (
				len == 2
				and s.get(start).to_int() == 46
				and s.get(start + 1).to_int() == 46
			): return false

			start = i + 1

	return true

// The path without the single trailing `/` a directory may carry.
fn clean(path: String, directory: Bool) String:
	if directory and path.ends_with("/"): return path.view(0, path.length() - 1).clone()
	return path.clone()

fn join_slash(name: Bytes) Bytes:
	var b = BytesBuilder()
	b.append_bytes(name)
	b.append(47)
	return b.build()

// A regular file sharing a path with an ancestor directory of another entry.
fn has_conflict(kinds: Map[String, Bool]) Bool:
	for key in kinds.keys():
		var dir = key.clone()

		while true:
			slash := dir.last_index_of("/")
			if slash.is_none(): break

			dir = dir.view(0, slash.get()).clone()

			is_directory := kinds.get(dir.clone())
			if is_directory.is_some() and not is_directory.get(): return true

	return false
