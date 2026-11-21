import (
	Bytes, BytesBuilder, join from "@std/bytes.ms",
	Utf8Scalar, decode_first from "@std/data/utf8.ms",
	from_scalars from "@std/string.ms",
	StringBuilder from "@std/string_builder.ms",
)

// URLs follow RFC 3986 as Go's `net/url` reads it, not the WHATWG URL Standard that
// browsers implement: there is no IDNA, IPv4 canonicalization or default-port removal.
// A parsed `Url` is an absolute hierarchical URL with a scheme. User information and
// opaque URLs (`mailto:x`) are rejected. A semicolon in a query is ordinary text, never
// a separator.

// One decoded key and value in a URL query string.
export type QueryEntry:
	// Decoded query key; duplicate keys retain separate entries in input order.
	key: String
	// Decoded query value; a bare key has an empty value and plus decodes as a space.
	value: String

// Parsed URL components. A missing port is represented by `none`.
export type Url:
	// URL scheme, lowercased during parsing; native parse rejects missing schemes and
	// opaque URLs.
	scheme: String
	// Lowercased hostname, excluding the port and IPv6 brackets; an IPv6 zone
	// identifier keeps its case. User information is rejected.
	host: String
	// Escaped path text, retaining escaped separators; format validates its percent
	// escapes and UTF-8.
	path: String
	// Decoded fragment contents without the leading hash mark.
	fragment: String
	// Encoded query contents without the leading question mark, or none when the URL
	// has no query; `http://a/b?` has an empty one. parse_query decodes individual
	// entries.
	query: String?
	// Explicit numeric port in 0..65535, or none when the input has no port.
	port: Int?
	// True when the URL was written without `//`, as in `mailto:?subject=hi`; format
	// then omits the empty authority, so the text round-trips.
	omit_host: Bool = false

// Decodes one percent-encoded URL component. `+` is not treated as a space.
export fn decode_component(text: String) String!:
	if not text.contains("%"): return ok(text.clone())

	decoded := unescape(text.to_bytes(), MODE_SEGMENT)
	if decoded.is_none(): return error(invalid_data())

	text_out := decoded.get_or("".to_bytes()).decode_utf8()
	if text_out.is_none(): return error(invalid_data())

	return ok(text_out.get_or(""))

// Percent-encodes one URL component using UTF-8 bytes.
export fn encode_component(text: String) String:
	bytes := text.view_bytes()
	hex := HEX_DIGITS.view_bytes()
	var out = BytesBuilder()
	var changed = false

	for i in 0..bytes.length():
		c := byte_at(bytes, i)

		if is_alnum(c) or c == 45 or c == 46 or c == 95 or c == 126:
			out.append(bytes.get(i))
		else:
			changed = true
			out.append(37)
			out.append(hex.get(c / 16))
			out.append(hex.get(c % 16))

	if not changed: return text.clone()

	return out.build().decode_utf8().get_or("")

// Formats URL components as an absolute hierarchical URL. Missing or malformed schemes
// and hostless relative paths return EINVAL, as do other invalid components.
export fn format(value: Url) String!:
	text := format_checked(value)
	if text.is_none(): return error(invalid_input())

	return ok(text.get_or(""))

// Encodes query entries as a query string.
export fn format_query(entries: List[QueryEntry]) String:
	var out = StringBuilder()

	for i in 0..entries.length():
		if i > 0: out.append("&")

		entry := entries.get(i)
		out.append(escape(entry.key.to_bytes(), MODE_QUERY).decode_utf8().get_or(""))
		out.append("=")
		out.append(escape(entry.value.to_bytes(), MODE_QUERY).decode_utf8().get_or(""))

	return out.build()

// Parses an absolute URL into its components.
export fn parse(text: String) Url!:
	url := parse_checked(text)
	if url.is_none(): return error(invalid_data())

	return ok(
		url.get_or(
			Url(
				scheme: "",
				host: "",
				path: "",
				fragment: "",
				query: none,
				port: none,
			)
		)
	)

// Parses a query string, preserving duplicate keys and their input order.
export fn parse_query(text: String, max_entries: Int?) List[QueryEntry]!:
	var limit = 9223372036854775807

	if max_entries.is_some():
		limit = max_entries.get_or(0)
		if limit < 0: return error(invalid_input())

	var entries: List[QueryEntry] = []
	if text.is_empty(): return ok(entries)

	for part in text.split("&"):
		if part.is_empty(): continue
		if entries.length() >= limit: return error(
			Error("URL: limit exceeded", kind: "EOVERFLOW")
		)

		equals := part.index_of("=")
		var key_text = part.clone()
		var value_text = ""

		if equals.is_some():
			key_text = part.slice(0, equals.get_or(0))
			value_text = part.slice(equals.get_or(0) + 1, part.length())

		key := unescape(key_text.to_bytes(), MODE_QUERY)
		value := unescape(value_text.to_bytes(), MODE_QUERY)
		if key.is_none() or value.is_none(): return error(invalid_data())

		key_string := key.get_or("".to_bytes()).decode_utf8()
		value_string := value.get_or("".to_bytes()).decode_utf8()
		if key_string.is_none() or value_string.is_none(): return error(invalid_data())

		entries.append(
			QueryEntry(
				key: key_string.get_or(""),
				value: value_string.get_or(""),
			)
		)

	return ok(entries)

// Resolves a relative reference against a base URL.
export fn resolve(base: Url, reference: String) Url!:
	b := build_url(base)
	if b.is_none(): return error(invalid_input())

	base_url := b.get_or(empty_url())
	if not valid_url(base_url): return error(invalid_input())

	r := parse_raw(reference.to_bytes())
	if r.is_none(): return error(invalid_data())

	ref_url := r.get_or(empty_url())
	if ref_url.has_user: return error(invalid_data())

	resolved := to_url(resolve_reference(base_url, ref_url))
	if resolved.is_none(): return error(invalid_data())

	return ok(
		resolved.get_or(
			Url(
				scheme: "",
				host: "",
				path: "",
				fragment: "",
				query: none,
				port: none,
			)
		)
	)

// ---- parser (Go's net/url over bytes: unescaped text can be invalid UTF-8) ----

// What the parser reads as Go's `url.URL`. User information is reduced to a flag: no
// public function exposes it.
type RawUrl:
	scheme: Bytes
	opaque: Bytes
	has_user: Bool
	host: Bytes
	path: Bytes
	raw_path: Bytes
	omit_host: Bool
	force_query: Bool
	raw_query: Bytes
	fragment: Bytes
	raw_fragment: Bytes

fn var RawUrl.set_path(p: Bytes) Bool:
	if is_canonical(p, MODE_PATH):
		self.path = p.clone()
		self.raw_path = "".to_bytes()
		return true

	decoded := unescape(p, MODE_PATH)
	if decoded.is_none(): return false

	path := decoded.get_or("".to_bytes())

	if escape(path, MODE_PATH) == p:
		self.raw_path = "".to_bytes()
	else:
		self.raw_path = p.clone()

	self.path = path
	return true

fn var RawUrl.set_fragment(f: Bytes) Bool:
	if is_canonical(f, MODE_FRAGMENT):
		self.fragment = f.clone()
		self.raw_fragment = "".to_bytes()
		return true

	decoded := unescape(f, MODE_FRAGMENT)
	if decoded.is_none(): return false

	fragment := decoded.get_or("".to_bytes())

	if escape(fragment, MODE_FRAGMENT) == f:
		self.raw_fragment = "".to_bytes()
	else:
		self.raw_fragment = f.clone()

	self.fragment = fragment
	return true

fn RawUrl.escaped_path() Bytes:
	if not self.raw_path.is_empty() and valid_encoded(self.raw_path, MODE_PATH):
		decoded := unescape(self.raw_path, MODE_PATH)
		if decoded.is_some() and decoded.get_or("".to_bytes()) == self.path: return (
			self
			.raw_path
			.clone()
		)

	if self.path == "*".to_bytes(): return self.path.clone()

	return escape(self.path, MODE_PATH)

fn RawUrl.escaped_fragment() Bytes:
	if (
		not self.raw_fragment.is_empty()
		and valid_encoded(self.raw_fragment, MODE_FRAGMENT)
	):
		decoded := unescape(self.raw_fragment, MODE_FRAGMENT)
		if decoded.is_some() and decoded.get_or("".to_bytes()) == self.fragment: return (
			self
			.raw_fragment
			.clone()
		)

	return escape(self.fragment, MODE_FRAGMENT)

// Go's `URL.String`.
fn RawUrl.render() Bytes:
	var out = BytesBuilder()

	if not self.scheme.is_empty():
		out.append_bytes(self.scheme)
		out.append(58)

	if not self.opaque.is_empty():
		out.append_bytes(self.opaque)
	else:
		var wrote = (
			not self.scheme.is_empty()
			or not self.host.is_empty()
			or self.has_user
		)

		if (
			wrote
			and not (
				self.omit_host
				and self.host.is_empty()
				and not self.has_user
			)
		):
			if not self.host.is_empty() or not self.path.is_empty() or self.has_user:
				out.append_bytes("//".to_bytes())
			if not self.host.is_empty(): out.append_bytes(escape(self.host, MODE_HOST))

		path := self.escaped_path()
		if not path.is_empty() and byte_at(path, 0) != 47 and not self.host.is_empty():
			out.append(47)

		slash := find_byte(path, 47)
		var segment = path.clone()
		if slash >= 0: segment = sub(path, 0, slash)

		nothing_yet := (
			self.scheme.is_empty()
			and self.host.is_empty()
			and not self.has_user
		)
		if nothing_yet and has_byte(segment, 58): out.append_bytes("./".to_bytes())
		out.append_bytes(path)

	if self.force_query or not self.raw_query.is_empty():
		out.append(63)
		out.append_bytes(self.raw_query)

	if not self.fragment.is_empty():
		out.append(35)
		out.append_bytes(self.escaped_fragment())

	return out.build()

// A host and whether the authority carried user information.
type Authority:
	has_user: Bool
	host: Bytes

// A host name and its port digits.
type HostPort:
	host: Bytes
	port: Bytes

// Escaping rules, as in Go's `shouldEscape`.
MODE_PATH := 0
MODE_SEGMENT := 1
MODE_HOST := 2
MODE_ZONE := 3
MODE_USER := 4
MODE_QUERY := 5
MODE_FRAGMENT := 6
HEX_DIGITS := "0123456789ABCDEF"

fn empty_url() RawUrl:
	none_bytes := "".to_bytes()
	return RawUrl(
		scheme: none_bytes.clone(),
		opaque: none_bytes.clone(),
		has_user: false,
		host: none_bytes.clone(),
		path: none_bytes.clone(),
		raw_path: none_bytes.clone(),
		omit_host: false,
		force_query: false,
		raw_query: none_bytes.clone(),
		fragment: none_bytes.clone(),
		raw_fragment: none_bytes.clone(),
	)

fn byte_at(s: Bytes, i: Int) Int:
	return s.get(i).to_int()

fn is_alnum(c: Int) Bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

fn is_hex(c: Int) Bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 70) or (c >= 97 and c <= 102)

fn unhex(c: Int) Int:
	if c >= 48 and c <= 57: return c - 48
	if c >= 97 and c <= 102: return c - 87
	if c >= 65 and c <= 70: return c - 55

	return 0

// Copies the bytes [start, end).
fn sub(s: Bytes, start: Int, end: Int) Bytes:
	return s.view(start, end).clone()

fn bytes_of(text: String) Bytes:
	return text.to_bytes()

// The offset of the first `c` in `s`, or -1.
fn find_byte(s: Bytes, c: Int) Int:
	for i in 0..s.length():
		if byte_at(s, i) == c: return i
	return -1

// The offset of the last `c` in `s`, or -1.
fn rfind_byte(s: Bytes, c: Int) Int:
	var i = s.length() - 1

	while i >= 0:
		if byte_at(s, i) == c: return i

		i -= 1

	return -1

fn has_byte(s: Bytes, c: Int) Bool:
	return find_byte(s, c) >= 0

// Whether `c` stays literal in a host or zone.
fn host_safe(c: Int) Bool:
	return (
		c == 33
		or c == 36
		or c == 38
		or c == 39
		or c == 40
		or c == 41
		or c == 42
		or c == 43
		or c == 44
		or c == 59
		or c == 61
		or c == 58
		or c == 91
		or c == 93
		or c == 60
		or c == 62
		or c == 34
	)

fn should_escape(c: Int, mode: Int) Bool:
	if is_alnum(c): return false
	if (mode == MODE_HOST or mode == MODE_ZONE) and host_safe(c): return false
	if c == 45 or c == 95 or c == 46 or c == 126: return false

	reserved := (
		c == 36
		or c == 38
		or c == 43
		or c == 44
		or c == 47
		or c == 58
		or c == 59
		or c == 61
		or c == 63
		or c == 64
	)

	if reserved:
		if mode == MODE_PATH: return c == 63
		if mode == MODE_SEGMENT: return c == 47 or c == 59 or c == 44 or c == 63
		if mode == MODE_USER: return c == 64 or c == 47 or c == 63 or c == 58
		if mode == MODE_QUERY: return true
		if mode == MODE_FRAGMENT: return false

	if mode == MODE_FRAGMENT and (c == 33 or c == 40 or c == 41 or c == 42): return false

	return true

// Text with no percent sign and no byte `mode` would escape reads as itself.
fn is_canonical(s: Bytes, mode: Int) Bool:
	for i in 0..s.length():
		c := byte_at(s, i)
		if c == 37 or should_escape(c, mode): return false

	return true

fn unescape(s: Bytes, mode: Int) Bytes?:
	n := s.length()
	var escapes = 0
	var has_plus = false
	var i = 0

	while i < n:
		c := byte_at(s, i)

		if c == 37:
			escapes += 1
			if (
				i + 2 >= n
				or not is_hex(byte_at(s, i + 1))
				or not is_hex(byte_at(s, i + 2))
			):
				return none

			is_25 := byte_at(s, i + 1) == 50 and byte_at(s, i + 2) == 53
			if mode == MODE_HOST and unhex(byte_at(s, i + 1)) < 8 and not is_25: return none

			if mode == MODE_ZONE:
				v := unhex(byte_at(s, i + 1)) * 16 + unhex(byte_at(s, i + 2))
				if not is_25 and v != 32 and should_escape(v, MODE_HOST): return none

			i += 3
		else if c == 43:
			has_plus = mode == MODE_QUERY
			i += 1
		else:
			if (
				(mode == MODE_HOST or mode == MODE_ZONE)
				and c < 128
				and should_escape(c, mode)
			):
				return none

			i += 1

	if escapes == 0 and not has_plus: return s.clone()

	var out = BytesBuilder()
	i = 0

	while i < n:
		c := byte_at(s, i)

		if c == 37:
			value := unhex(byte_at(s, i + 1)) * 16 + unhex(byte_at(s, i + 2))
			out.append(value.to_uint8().get_or(0))
			i += 3
		else if c == 43 and mode == MODE_QUERY:
			out.append(32)
			i += 1
		else:
			out.append(s.get(i))
			i += 1

	return out.build()

fn escape(s: Bytes, mode: Int) Bytes:
	var first = -1

	for i in 0..s.length():
		if should_escape(byte_at(s, i), mode):
			first = i
			break

	if first < 0: return s.clone()

	hex := HEX_DIGITS.view_bytes()
	var out = BytesBuilder()
	out.append_bytes(s.view(0, first))

	for i in first..s.length():
		c := byte_at(s, i)

		if c == 32 and mode == MODE_QUERY:
			out.append(43)
		else if should_escape(c, mode):
			out.append(37)
			out.append(hex.get(c / 16))
			out.append(hex.get(c % 16))
		else:
			out.append(s.get(i))

	return out.build()

// The offset of the colon ending a scheme, -1 for none, -2 for an empty scheme.
fn scheme_end(raw: Bytes) Int:
	for i in 0..raw.length():
		c := byte_at(raw, i)
		if (c >= 97 and c <= 122) or (c >= 65 and c <= 90): continue

		if (c >= 48 and c <= 57) or c == 43 or c == 45 or c == 46:
			if i == 0: return -1

			continue

		if c == 58:
			if i == 0: return -2
			return i

		return -1

	return -1

fn lower_ascii(s: Bytes) Bytes:
	var out = BytesBuilder()

	for i in 0..s.length():
		c := byte_at(s, i)

		if c >= 65 and c <= 90:
			out.append((c + 32).to_uint8().get_or(0))
		else:
			out.append(s.get(i))

	return out.build()

fn has_ctl(s: Bytes) Bool:
	for i in 0..s.length():
		c := byte_at(s, i)
		if c < 32 or c == 127: return true

	return false

fn starts(s: Bytes, prefix: String) Bool:
	return s.starts_with(prefix.to_bytes())

fn valid_optional_port(s: Bytes, from: Int) Bool:
	if from >= s.length(): return true
	if byte_at(s, from) != 58: return false

	for i in from + 1..s.length():
		c := byte_at(s, i)
		if c < 48 or c > 57: return false

	return true

fn valid_userinfo(s: Bytes) Bool:
	for i in 0..s.length():
		c := byte_at(s, i)
		ok := (
			is_alnum(c)
			or c == 45
			or c == 46
			or c == 95
			or c == 58
			or c == 126
			or c == 33
			or c == 36
			or c == 38
			or c == 39
			or c == 40
			or c == 41
			or c == 42
			or c == 43
			or c == 44
			or c == 59
			or c == 61
			or c == 37
			or c == 64
		)
		if not ok: return false

	return true

// The offset of `needle` in `s`, or -1.
fn find_text(s: Bytes, needle: String) Int:
	return s.index_of(needle.to_bytes()).get_or(-1)

fn parse_host(host: Bytes) Bytes?:
	n := host.length()

	if n > 0 and byte_at(host, 0) == 91:
		i := rfind_byte(host, 93)
		if i < 0: return none
		if not valid_optional_port(host, i + 1): return none

		zone := find_text(host.view(0, i), "%25")

		if zone >= 0:
			head := unescape(host.view(0, zone), MODE_HOST)?
			middle := unescape(host.view(zone, i), MODE_ZONE)?
			tail := unescape(host.view(i, n), MODE_HOST)?
			return join([head, middle, tail])
	else:
		colon := rfind_byte(host, 58)
		if colon >= 0 and not valid_optional_port(host, colon): return none

	return unescape(host, MODE_HOST)

fn parse_authority(authority: Bytes) Authority?:
	at := rfind_byte(authority, 64)

	if at < 0:
		host := parse_host(authority)?
		return Authority(has_user: false, host: host)

	host := parse_host(authority.view(at + 1, authority.length()))?
	userinfo := authority.view(0, at)
	if not valid_userinfo(userinfo): return none

	colon := find_byte(userinfo, 58)

	if colon < 0:
		_name := unescape(userinfo, MODE_USER)?
	else:
		_name := unescape(userinfo.view(0, colon), MODE_USER)?
		_pass := unescape(userinfo.view(colon + 1, userinfo.length()), MODE_USER)?

	return Authority(has_user: true, host: host)

fn parse_inner(raw: Bytes) RawUrl?:
	if has_ctl(raw): return none

	var url = empty_url()

	if raw == "*".to_bytes():
		url.path = "*".to_bytes()
		return url

	colon := scheme_end(raw)
	if colon == -2: return none

	var rest = raw.clone()

	if colon >= 0:
		url.scheme = lower_ascii(sub(raw, 0, colon))
		rest = sub(raw, colon + 1, raw.length())

	var question = find_byte(rest, 63)
	only_question := (
		question >= 0
		and question == rest.length() - 1
		and rfind_byte(rest, 63) == question
	)

	if only_question:
		url.force_query = true
		rest = sub(rest, 0, question)
	else if question >= 0:
		url.raw_query = sub(rest, question + 1, rest.length())
		rest = sub(rest, 0, question)

	has_scheme := not url.scheme.is_empty()

	if not starts(rest, "/"):
		if has_scheme:
			url.opaque = rest.clone()

			// No `//` was written; with an empty opaque part this is
			// `mailto:?subject=hi`.
			url.omit_host = true
			return url

		slash := find_byte(rest, 47)
		var segment = rest.clone()
		if slash >= 0: segment = sub(rest, 0, slash)
		if has_byte(segment, 58): return none

	if (has_scheme or not starts(rest, "///")) and starts(rest, "//"):
		var authority = sub(rest, 2, rest.length())
		var tail = "".to_bytes()
		slash := find_byte(authority, 47)

		if slash >= 0:
			tail = sub(authority, slash, authority.length())
			authority = sub(authority, 0, slash)

		parsed := parse_authority(authority)?
		url.has_user = parsed.has_user
		url.host = parsed.host
		if not url.set_path(tail): return none

		return url

	if has_scheme and starts(rest, "/"): url.omit_host = true
	if not url.set_path(rest): return none

	return url

// Go's `url.Parse`.
fn parse_raw(raw: Bytes) RawUrl?:
	hash := find_byte(raw, 35)
	if hash < 0: return parse_inner(raw)

	var url = parse_inner(raw.view(0, hash))?
	if hash + 1 < raw.length():
		if not url.set_fragment(raw.view(hash + 1, raw.length())): return none
	return url

fn valid_encoded(s: Bytes, mode: Int) Bool:
	for i in 0..s.length():
		c := byte_at(s, i)
		literal := (
			c == 33
			or c == 36
			or c == 38
			or c == 39
			or c == 40
			or c == 41
			or c == 42
			or c == 43
			or c == 44
			or c == 59
			or c == 61
			or c == 58
			or c == 64
			or c == 91
			or c == 93
			or c == 37
		)
		if not literal and should_escape(c, mode): return false

	return true

// Go's `resolvePath`.
fn resolve_path(base: Bytes, r: Bytes) Bytes:
	var full = r.clone()

	if r.is_empty():
		full = base
	else if byte_at(r, 0) != 47:
		slash := rfind_byte(base, 47)
		full = join([sub(base, 0, slash + 1), r])

	if full.is_empty(): return "".to_bytes()

	var dst = [47]
	var first = true
	var start = 0
	var elem_start = 0
	var elem_end = 0

	while true:
		slash := full.index_of_byte(47, start).get_or(-1)
		elem_start = start
		elem_end = slash
		if slash < 0: elem_end = full.length()

		length := elem_end - elem_start
		is_dot := length == 1 and byte_at(full, elem_start) == 46
		is_dot_dot := (
			length == 2
			and byte_at(full, elem_start) == 46
			and byte_at(full, elem_start + 1) == 46
		)

		if is_dot:
			first = false
		else if is_dot_dot:
			// Drop the last element and its slash, or reset to the root.
			var index = -1
			var k = dst.length() - 1

			while k >= 1:
				if dst.get(k) == 47:
					index = k
					break

				k -= 1

			if index < 0:
				while dst.length() > 1: dst.pop()
				first = true
			else:
				while dst.length() > index: dst.pop()
		else:
			if not first: dst.append(47)
			for k in elem_start..elem_end: dst.append(byte_at(full, k))
			first = false

		if slash < 0: break

		start = slash + 1

	length := elem_end - elem_start
	last_dot := length == 1 and byte_at(full, elem_start) == 46
	last_dot_dot := (
		length == 2
		and byte_at(full, elem_start) == 46
		and byte_at(full, elem_start + 1) == 46
	)
	if last_dot or last_dot_dot: dst.append(47)
	if dst.length() > 1 and dst.get(1) == 47: dst.remove(0)

	var out = BytesBuilder()
	for b in dst: out.append(b.to_uint8().get_or(0))
	return out.build()

// ---- components ----

// Lowercases text that may hold invalid UTF-8: a scalar maps to the first scalar of its
// lowercase form, each bad byte becomes U+FFFD. `lower` false only repairs.
fn lossy_text(b: Bytes, lower: Bool) String:
	var out = StringBuilder()
	var i = 0

	while i < b.length():
		var c = byte_at(b, i)

		if c < 128:
			if lower and c >= 65 and c <= 90: c += 32
			out.append(from_scalars([c]).get_or(""))
			i += 1
			continue

		decoded := decode_first(b, i)

		if decoded.is_error():
			out.append("\u{FFFD}")
			i += 1
			continue

		scalar := decoded.get_or(Utf8Scalar(scalar: 65533, width: 1))
		var text = from_scalars([scalar.scalar]).get_or("")
		if lower: text = from_scalars([text.lower().scalar_at(0, scalar.scalar)]).get_or(
			text
		)
		out.append(text)
		i += scalar.width

	return out.build()

fn go_lower(b: Bytes) String:
	return lossy_text(b, true)

// Lowercases a hostname but keeps an IPv6 zone identifier (after the first `%`).
fn go_lower_host(host: Bytes) String:
	i := find_byte(host, 37)
	if i < 0: return go_lower(host)

	return go_lower(host.view(0, i)) + lossy_text(host.view(i, host.length()), false)

fn split_host_port(host_port: Bytes) HostPort:
	var host = host_port.clone()
	var port = "".to_bytes()
	colon := rfind_byte(host_port, 58)

	if colon >= 0 and valid_optional_port(host_port, colon):
		port = sub(host_port, colon + 1, host_port.length())
		host = sub(host_port, 0, colon)

	n := host.length()
	if n >= 2 and byte_at(host, 0) == 91 and byte_at(host, n - 1) == 93:
		host = sub(host, 1, n - 1)
	return HostPort(host: host.clone(), port: port)

fn valid_query(query: Bytes) Bool:
	n := query.length()

	for i in 0..n:
		c := byte_at(query, i)
		if c == 35 or c == 32 or c < 32 or c == 127: return false
		if (
			c == 37
			and (
				i + 2 >= n
				or not is_hex(byte_at(query, i + 1))
				or not is_hex(byte_at(query, i + 2))
			)
		):
			return false

	return true

fn to_url(u: RawUrl) Url?:
	if u.has_user or not u.opaque.is_empty() or u.scheme.is_empty(): return none

	hp := split_host_port(u.host.clone())
	var port: Int? = none

	if not hp.port.is_empty():
		var n = 0

		for i in 0..hp.port.length():
			n = n * 10 + byte_at(hp.port, i) - 48
			if n > 65535: return none

		port = n

	_path := u.path.decode_utf8()?
	fragment := u.fragment.decode_utf8()?
	if not valid_query(u.raw_query): return none

	// Only a bracketed IP literal may contain a colon; "host:80:80" is malformed.
	if has_byte(hp.host, 58) and not starts(u.host, "["): return none

	var query: String? = none
	if u.force_query or not u.raw_query.is_empty(): query = u.raw_query.decode_utf8()?
	return Url(
		scheme: go_lower(u.scheme),
		host: go_lower_host(hp.host),
		path: u.escaped_path().decode_utf8()?,
		fragment: fragment,
		query: query,
		port: port,
		omit_host: u.omit_host,
	)

// Rebuilds a Go URL from components, once their parts pass the cheap checks.
fn build_url(v: Url) RawUrl?:
	var host = BytesBuilder()

	// net.JoinHostPort: a colon in the host means an IPv6 literal, which takes
	// brackets.
	bracket := v.host.contains(":")
	if bracket: host.append_bytes("[".to_bytes())
	host.append_bytes(v.host.to_bytes())
	if bracket: host.append_bytes("]".to_bytes())

	if v.port.is_some():
		n := v.port.get_or(0)
		if n < 0 or n > 65535: return none

		host.append_bytes(f":{n}".to_bytes())

	host_bytes := host.build()
	raw := v.path.to_bytes()

	// Without an authority, a relative path would be serialized as a hostname.
	if host_bytes.is_empty() and not raw.is_empty() and byte_at(raw, 0) != 47: return none

	decoded := unescape(raw, MODE_SEGMENT)?
	_valid := decoded.decode_utf8()?

	// An IPv6 zone identifier may hold any text, which `render` escapes.
	percent := find_byte(host_bytes, 37)
	var address = host_bytes.clone()
	if percent >= 0: address = sub(host_bytes, 0, percent)

	query := v.query.get_or("").to_bytes()
	if not valid_query(query): return none

	for i in 0..address.length():
		c := byte_at(address, i)
		if c == 32 or c == 60 or c == 62 or c == 34: return none

	var url = empty_url()
	url.scheme = v.scheme.to_bytes()
	url.host = host_bytes
	url.path = decoded
	url.raw_path = raw
	url.raw_query = query
	url.fragment = v.fragment.to_bytes()
	url.omit_host = v.omit_host
	url.force_query = v.query.is_some() and v.query.get_or("x").is_empty()
	return url

// The reference check: parse what `render` wrote and require a hierarchical URL with
// the same scheme, no userinfo and no host byte that would change the authority.
fn reparses(u: RawUrl, rendered: Bytes) Bool:
	parsed := parse_raw(rendered)
	if parsed.is_none(): return false

	p := parsed.get_or(empty_url())
	if p.scheme.is_empty() or not p.opaque.is_empty() or p.has_user: return false
	if lower_ascii(p.scheme) != lower_ascii(u.scheme): return false

	for i in 0..u.host.length():
		c := byte_at(u.host, i)
		if c == 47 or c == 64 or c == 92 or c == 13 or c == 10: return false

	return true

fn valid_url(u: RawUrl) Bool:
	return reparses(u, u.render())

fn format_checked(v: Url) String?:
	u := build_url(v)?
	rendered := u.render()
	if not reparses(u, rendered): return none

	// A bare scheme would read as an opaque URL, so an empty hierarchical part keeps
	// `//` unless the URL was read without one.
	if u.host.is_empty() and u.path.is_empty() and not u.omit_host:
		at := u.scheme.length() + 1
		return join(
			[
				sub(rendered, 0, at),
				"//".to_bytes(),
				sub(rendered, at, rendered.length()),
			]
		).decode_utf8()

	return rendered.decode_utf8()

fn parse_checked(text: String) Url?:
	u := parse_raw(text.to_bytes())?
	if u.scheme.is_empty() or u.has_user: return none

	return to_url(u)

// Go's `URL.ResolveReference`.
fn resolve_reference(base: RawUrl, r: RawUrl) RawUrl:
	var url = r.clone()
	if r.scheme.is_empty(): url.scheme = base.scheme.clone()

	if not r.scheme.is_empty() or not r.host.is_empty() or r.has_user:
		url.set_path(resolve_path(r.escaped_path(), "".to_bytes()))
		return url

	if not r.opaque.is_empty():
		url.has_user = false
		url.host = "".to_bytes()
		url.path = "".to_bytes()
		return url

	if r.path.is_empty() and not r.force_query and r.raw_query.is_empty():
		url.raw_query = base.raw_query.clone()

		if r.fragment.is_empty():
			url.fragment = base.fragment.clone()
			url.raw_fragment = base.raw_fragment.clone()

	if r.path.is_empty() and not base.opaque.is_empty():
		url.opaque = base.opaque.clone()
		url.has_user = false
		url.host = "".to_bytes()
		url.path = "".to_bytes()
		return url

	url.host = base.host.clone()
	url.has_user = base.has_user
	url.set_path(resolve_path(base.escaped_path(), r.escaped_path()))
	return url

fn invalid_data() Error:
	return Error("URL: invalid data", kind: "EBADMSG")

fn invalid_input() Error:
	return Error("URL: invalid input", kind: "EINVAL")
