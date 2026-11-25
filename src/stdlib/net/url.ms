import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	panic from "@std/core.ms",
	JsonValue from "@std/data/json.ms",
)

// URLs follow RFC 3986 as Go's `net/url` reads it, not the WHATWG URL Standard that
// browsers implement: there is no IDNA, IPv4 canonicalization or default-port removal.
// A parsed `Url` is an absolute hierarchical URL with a scheme. User information and
// opaque URLs (`mailto:x`) are rejected. A semicolon in a query is ordinary text, never
// a separator.

// One decoded key and value in a URL query string.
export type QueryEntry {
	// Decoded query key; duplicate keys retain separate entries in input order.
	key String
	// Decoded query value; a bare key has an empty value and plus decodes as a space.
	value String
}

// Parsed URL components. A missing port is represented by `null`.
export type Url {
	// URL scheme, lowercased during parsing; native parse rejects missing schemes and
	// opaque URLs.
	scheme String
	// Lowercased hostname, excluding the port and IPv6 brackets; an IPv6 zone
	// identifier keeps its case. User information is rejected.
	host String
	// Escaped path text, retaining escaped separators; format validates its percent
	// escapes and UTF-8.
	path String
	// Decoded fragment contents without the leading hash mark.
	fragment String
	// Encoded query contents without the leading question mark, or null when the URL
	// has no query; `http://a/b?` has an empty one. parse_query decodes individual
	// entries.
	query String?
	// Explicit numeric port in 0..65535, or null when the input has no port.
	port Int?
	// True when the URL was written without `//`, as in `mailto:?subject=hi`; format
	// then omits the empty authority, so the text round-trips.
	omit_host Bool = false
}

// Writes the formatted URL as a JSON string; components `format` rejects fault.
fn Url.to_json() JsonValue {
	text := format(self).get_or_else(cause => panic(f"Url.to_json: {cause.message}"))
	return JsonValue.StringValue(text.clone())
}

// ---- percent escaping, by the rules of Go's net/url ----
//
// The escaping modes are ints: 0 path, 1 path segment, 2 host, 3 IPv6 zone, 4 user
// information, 5 query component, 6 fragment. Text is held as bytes because it may be
// invalid UTF-8 after unescaping.

fn invalid_data[T]() T! {
	return error(Error("URL: invalid data", kind: "EBADMSG"))
}

fn invalid_input[T]() T! {
	return error(Error("URL: invalid input", kind: "EINVAL"))
}

fn text_of(data Bytes) String! {
	text := data.decode_utf8()
	if text == null { return invalid_data() }

	return ok(text)
}

fn is_alnum(c Int) Bool {
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
}

// The value of a hexadecimal digit, or -1.
fn hex_value(c Int) Int {
	if c >= 48 and c <= 57 { return c - 48 }
	if c >= 65 and c <= 70 { return c - 55 }
	if c >= 97 and c <= 102 { return c - 87 }

	return -1
}

fn hex_digit(value Int) UInt8 {
	if value < 10 { return (48 + value).to_uint8() or 0 }
	return (55 + value).to_uint8() or 0
}

// Bytes a host or zone keeps unescaped: ! " $ & ' ( ) * + , : ; < = > [ ]
fn host_safe(c Int) Bool {
	if c >= 33 and c <= 44 { return c != 35 and c != 37 }
	return c >= 58 and c <= 62 or c == 91 or c == 93
}

// Whether a reserved byte (one of `$&+,/:;=?@`) is escaped in `mode`.
fn reserved_escapes(c, mode Int) Bool {
	if mode == 0 { return c == 63 }
	if mode == 1 { return c == 47 or c == 59 or c == 44 or c == 63 }
	if mode == 4 { return c == 64 or c == 47 or c == 63 or c == 58 }
	if mode == 6 { return false }

	return true
}

// Letters, digits and `-._~`: never escaped in any mode.
fn unreserved(c Int) Bool {
	return is_alnum(c) or c == 45 or c == 46 or c == 95 or c == 126
}

fn should_escape(c, mode Int) Bool {
	if (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or (c >= 48 and c <= 57) { return false }

	host := mode == 2 or mode == 3
	if host and host_safe(c) { return false }
	if c == 45 or c == 95 or c == 46 or c == 126 { return false }

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
	if reserved and not host { return reserved_escapes(c, mode) }
	if mode == 6 and (c == 33 or c == 40 or c == 41 or c == 42) { return false }

	return true
}

fn escape(text Bytes, mode Int) Bytes {
	var plain = true

	for i in 0..text.length() {
		c := text.get(i).to_int()

		if not unreserved(c) and should_escape(c, mode) {
			plain = false
			break
		}
	}

	if plain { return text.clone() }

	var out = BytesBuilder()

	for i in 0..text.length() {
		c := text.get(i).to_int()

		if c == 32 and mode == 5 {
			out.append(43)
		} else if should_escape(c, mode) {
			out.append(37)
			out.append(hex_digit(c / 16))
			out.append(hex_digit(c % 16))
		} else {
			out.append(c.to_uint8() or 0)
		}
	}

	return out.build()
}

// Whether the escape at `text[i..i + 3]`, already well formed, is allowed in `mode`.
fn escape_allowed(text Bytes, i, mode Int) Bool {
	high := hex_value(text.get(i + 1).to_int())
	percent25 := text.get(i + 1).to_int() == 50 and text.get(i + 2).to_int() == 53
	if mode == 2 and high < 8 and not percent25 { return false }

	if mode == 3 {
		value := high * 16 + hex_value(text.get(i + 2).to_int())
		if not percent25 and value != 32 and should_escape(value, 2) { return false }
	}

	return true
}

// Go's unescape: null for a malformed escape or a byte the mode forbids.
fn unescape(text Bytes, mode Int) Bytes? {
	size := text.length()

	// Nothing to validate or rewrite without `%`, a query `+` or a host byte to check.
	if (
		mode != 2
		and mode != 3
		and text.index_of_byte(37, 0) == null
		and (mode != 5 or text.index_of_byte(43, 0) == null)
	) {
		return text.clone()
	}

	var rewrite = false
	var i = 0

	while i < size {
		c := text.get(i).to_int()

		if c == 37 {
			rewrite = true
			if i + 2 >= size { return null }
			if (
				hex_value(text.get(i + 1).to_int()) < 0
				or hex_value(text.get(i + 2).to_int()) < 0
			) { return null }
			if not escape_allowed(text, i, mode) { return null }

			i += 3
			continue
		}

		if c == 43 {
			if mode == 5 { rewrite = true }
		} else if (mode == 2 or mode == 3) and c < 128 and should_escape(c, mode) {
			return null
		}

		i += 1
	}

	if not rewrite { return text.clone() }

	var out = BytesBuilder()
	i = 0

	while i < size {
		c := text.get(i).to_int()

		if c == 37 {
			out.append(
				(
					hex_value(text.get(i + 1).to_int()) * 16
					+ hex_value(text.get(i + 2).to_int())
				).to_uint8() or 0
			)
			i += 3
		} else {
			if c == 43 and mode == 5 {
				out.append(32)
			} else {
				out.append(c.to_uint8() or 0)
			}

			i += 1
		}
	}

	return out.build()
}

// The bytes `data[start..stop]`.
fn sub(data Bytes, start, stop Int) Bytes {
	if start < 0 or start > stop or stop > data.length() { return empty() }
	return data.view(start, stop).clone()
}

// One `key=value` part of a query as a decoded entry, or null when it is malformed.
fn query_entry(data Bytes, start, stop Int) QueryEntry? {
	found := data.index_of_byte(61, start) or stop
	split := if found < stop { found } else { stop }
	key := unescape(sub(data, start, split), 5)
	if key == null { return null }

	value := unescape(
		if split < stop { sub(data, split + 1, stop) } else { "".to_bytes() },
		5,
	)
	if value == null { return null }

	key_text := key.decode_utf8()
	value_text := value.decode_utf8()
	if key_text == null or value_text == null { return null }

	return QueryEntry(key_text, value_text)
}

// ---- the parsed form: Go's url.URL over bytes ----

type Parts {
	scheme, opaque, host, path, raw_path, raw_query, fragment, raw_fragment, username, password Bytes
	has_user, password_set, omit_host, force_query Bool
}

fn empty() Bytes {
	return "".to_bytes()
}

fn new_parts() Parts {
	return Parts(
		empty(),
		empty(),
		empty(),
		empty(),
		empty(),
		empty(),
		empty(),
		empty(),
		empty(),
		empty(),
		false,
		false,
		false,
		false,
	)
}

fn is_alpha(c Int) Bool {
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
}

// The index of the last `byte` in `data`, or -1.
fn last_index(data Bytes, byte Int) Int {
	var i = data.length() - 1

	while i >= 0 {
		if data.get(i).to_int() == byte { return i }

		i -= 1
	}

	return -1
}

fn starts_with(data Bytes, prefix String) Bool {
	return data.starts_with(prefix.view_bytes())
}

// Go's getScheme: the length of the scheme (0 for none), or -1 for an empty scheme
// before `:`.
fn scheme_length(raw Bytes) Int {
	for i in 0..raw.length() {
		c := raw.get(i).to_int()
		if is_alpha(c) { continue }

		if (c >= 48 and c <= 57) or c == 43 or c == 45 or c == 46 {
			if i == 0 { return 0 }

			continue
		}

		if c == 58 { return if i == 0 { - 1 } else { i } }

		return 0
	}

	return 0
}

fn has_control(data Bytes) Bool {
	for i in 0..data.length() {
		c := data.get(i).to_int()
		if c < 32 or c == 127 { return true }
	}

	return false
}

fn userinfo_byte(c Int) Bool {
	return (
		is_alnum(c)
		or (c >= 36 and c <= 46 and c != 34)
		or c == 33
		or c == 58
		or c == 59
		or c == 61
		or c == 64
		or c == 95
		or c == 126
	)
}

fn valid_userinfo(data Bytes) Bool {
	for i in 0..data.length() {
		if not userinfo_byte(data.get(i).to_int()) { return false }
	}
	return true
}

// Whether `port` is empty or `:` and digits.
fn valid_optional_port(port Bytes) Bool {
	if port.is_empty() { return true }
	if port.get(0).to_int() != 58 { return false }

	for i in 1..port.length() {
		c := port.get(i).to_int()
		if c < 48 or c > 57 { return false }
	}

	return true
}

fn is_canonical(text Bytes, mode Int) Bool {
	for i in 0..text.length() {
		c := text.get(i).to_int()
		if c == 37 or should_escape(c, mode) { return false }
	}

	return true
}

// Whether `text` is a valid encoding in `mode`: every byte is allowed or an escape.
fn valid_encoded(text Bytes, mode Int) Bool {
	for i in 0..text.length() {
		c := text.get(i).to_int()
		if (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or (c >= 48 and c <= 57) { continue }
		if c == 45 or c == 46 or c == 95 or c == 126 { continue }

		allowed := (
			c == 33
			or c == 37
			or c == 58
			or c == 64
			or c == 91
			or c == 93
			or (c >= 36 and c <= 44 and c != 34 and c != 35)
		)
		if not allowed and should_escape(c, mode) { return false }
	}

	return true
}

// The host with its zone unescaped by the zone rules; `close` is the index of the last
// `]`.
fn parse_bracketed_host(host Bytes, close Int) Bytes? {
	var i = 0

	while i + 3 <= close {
		if (
			host.get(i).to_int() == 37
			and host.get(i + 1).to_int() == 50
			and host.get(i + 2).to_int() == 53
		) {
			before := unescape(host.view(0, i), 2)
			zone := unescape(host.view(i, close), 3)
			after := unescape(host.view(close, host.length()), 2)
			if before == null or zone == null or after == null { return null }

			return before.concat(zone).concat(after)
		}

		i += 1
	}

	return unescape(host, 2)
}

fn parse_host(host Bytes) Bytes? {
	if starts_with(host, "[") {
		at := last_index(host, 93)
		if at < 0 or not valid_optional_port(host.view(at + 1, host.length())) { return null }

		return parse_bracketed_host(host, at)
	}

	colon := last_index(host, 58)
	if colon >= 0 and not valid_optional_port(host.view(colon, host.length())) { return null }

	return unescape(host, 2)
}

fn parse_authority(authority Bytes, var url Parts) Bool {
	at := last_index(authority, 64)
	host := parse_host(
		authority.view(if at >= 0 { at + 1 } else { 0 }, authority.length())
	)
	if host == null { return false }

	url.host = host
	if at < 0 { return true }

	userinfo := authority.view(0, at)
	if not valid_userinfo(userinfo) { return false }

	colon := userinfo.index_of_byte(58, 0)
	url.has_user = true
	url.password_set = colon != null

	name := unescape(userinfo.view(0, colon or userinfo.length()), 4)
	if name == null { return false }

	url.username = name
	if colon == null { return true }

	password := unescape(userinfo.view(colon + 1, userinfo.length()), 4)
	if password == null { return false }

	url.password = password
	return true
}

fn set_path(var url Parts, path Bytes) Bool {
	if is_canonical(path, 0) {
		url.path = path.clone()
		url.raw_path = empty()
		return true
	}

	decoded := unescape(path, 0)
	if decoded == null { return false }

	url.raw_path = if escape(decoded, 0) != path { path.clone() } else { empty() }
	url.path = decoded
	return true
}

fn set_fragment(var url Parts, fragment Bytes) Bool {
	if is_canonical(fragment, 6) {
		url.fragment = fragment.clone()
		return true
	}

	decoded := unescape(fragment, 6)
	if decoded == null { return false }

	if escape(decoded, 6) != fragment { url.raw_fragment = fragment.clone() }
	url.fragment = decoded
	return true
}

// The part after the scheme and query: the authority, then the path.
fn parse_hierarchy(rest Bytes, var url Parts) Bool {
	var path_start = 0

	if (
		starts_with(rest, "//")
		and not (starts_with(rest, "///") and url.scheme.is_empty())
	) {
		slash := rest.view(2, rest.length()).index_of_byte(47, 0) or rest.length() - 2
		path_start = slash + 2
		if not parse_authority(rest.view(2, path_start), url) { return false }
	} else if not url.scheme.is_empty() and starts_with(rest, "/") {
		url.omit_host = true
	}

	return set_path(url, rest.view(path_start, rest.length()))
}

fn count_byte(data Bytes, byte Int) Int {
	var count = 0
	for i in 0..data.length() {
		if data.get(i).to_int() == byte { count += 1 }
	}
	return count
}

fn is_star(data Bytes) Bool {
	return data.length() == 1 and data.get(0).to_int() == 42
}

// 1 for ".", 2 for "..", else 0.
fn dot_count(data Bytes) Int {
	n := data.length()
	if n == 0 or n > 2 { return 0 }

	for i in 0..n {
		if data.get(i).to_int() != 46 { return 0 }
	}
	return n
}

fn lower_ascii(data Bytes) Bytes {
	var out = BytesBuilder()

	for i in 0..data.length() {
		c := data.get(i).to_int()
		out.append((if c >= 65 and c <= 90 { c + 32 } else { c }).to_uint8() or 0)
	}

	return out.build()
}

fn parse_inner(raw Bytes, var url Parts) Bool {
	if has_control(raw) { return false }

	if is_star(raw) {
		url.path = raw.clone()
		return true
	}

	size := scheme_length(raw)
	if size < 0 { return false }

	start := if size > 0 { size + 1 } else { 0 }
	var stop = raw.length()
	url.scheme = lower_ascii(raw.view(0, size))

	if (
		stop > start
		and raw.get(stop - 1).to_int() == 63
		and count_byte(raw.view(start, stop), 63) == 1
	) {
		url.force_query = true
		stop -= 1
	} else {
		mark := raw.view(start, stop).index_of_byte(63, 0)

		if mark != null {
			url.raw_query = sub(raw, start + mark + 1, stop)
			stop = start + mark
		}
	}

	rest := raw.view(start, stop)

	if not starts_with(rest, "/") {
		if not url.scheme.is_empty() {
			url.opaque = rest.clone()
			url.omit_host = true
			return true
		}

		slash := rest.index_of_byte(47, 0) or rest.length()
		if rest.view(0, slash).index_of_byte(
			58,
			0,
		) != null { return false }
	}

	return parse_hierarchy(rest, url)
}

// Go's url.Parse; null when the text is malformed.
fn parse_parts(raw Bytes) Parts? {
	hash := raw.index_of_byte(35, 0) or raw.length()
	var url = new_parts()
	if not parse_inner(raw.view(0, hash), url) { return null }
	if (
		hash + 1 < raw.length()
		and not set_fragment(url, raw.view(hash + 1, raw.length()))
	) { return null }

	return url
}

// ---- rendering, resolving and the public record ----

fn user_text(url Parts) Bytes {
	var out = BytesBuilder()
	out.append_bytes(escape(url.username, 4))

	if url.password_set {
		out.append(58)
		out.append_bytes(escape(url.password, 4))
	}

	return out.build()
}

// Whether `raw` is a non-empty valid encoding of exactly `plain` in `mode`.
fn raw_matches(raw, plain Bytes, mode Int) Bool {
	if raw.is_empty() or not valid_encoded(raw, mode) { return false }

	decoded := unescape(raw, mode)
	return decoded != null and decoded == plain
}

fn escaped_path(url Parts) Bytes {
	if raw_matches(url.raw_path, url.path, 0) { return url.raw_path.clone() }
	if is_star(url.path) { return url.path.clone() }

	return escape(url.path, 0)
}

fn escaped_fragment(url Parts) Bytes {
	if raw_matches(url.raw_fragment, url.fragment, 6) { return url.raw_fragment.clone() }
	return escape(url.fragment, 6)
}

// Go's URL.String.
fn render(url Parts) Bytes {
	var out = BytesBuilder()

	if not url.scheme.is_empty() {
		out.append_bytes(url.scheme)
		out.append(58)
	}

	if not url.opaque.is_empty() {
		out.append_bytes(url.opaque)
	} else {
		render_hierarchy(url, out)
	}

	if url.force_query or not url.raw_query.is_empty() {
		out.append(63)
		out.append_bytes(url.raw_query)
	}

	if not url.fragment.is_empty() {
		out.append(35)
		out.append_bytes(escaped_fragment(url))
	}

	return out.build()
}

// Appends the authority and path of a hierarchical URL to `out`.
fn render_hierarchy(url Parts, var out BytesBuilder) Void {
	host_empty := url.host.is_empty()
	has_authority := not host_empty or not url.path.is_empty() or url.has_user
	has_head := (
		(not url.scheme.is_empty() or not host_empty or url.has_user)
		and not (url.omit_host and host_empty and not url.has_user)
		and has_authority
	)

	if has_head {
		out.append(47)
		out.append(47)

		if url.has_user {
			out.append_bytes(user_text(url))
			out.append(64)
		}

		out.append_bytes(escape(url.host, 2))
	}

	path := escaped_path(url)
	if not path.is_empty() and path.get(
		0
	).to_int() != 47 and not host_empty { out.append(47) }

	segment := path.view(0, path.index_of_byte(47, 0) or path.length())

	if url.scheme.is_empty() and not has_head and segment.index_of_byte(58, 0) != null {
		out.append(46)
		out.append(47)
	}

	out.append_bytes(path)
}

// Go's resolvePath: `base` and `reference` are escaped paths.
fn resolve_path(base, reference Bytes) Bytes {
	var full = reference.clone()

	if reference.is_empty() {
		full = base.clone()
	} else if reference.get(0).to_int() != 47 {
		full = sub(base, 0, last_index(base, 47) + 1).concat(reference)
	}

	if full.is_empty() { return empty() }

	var dst = "/".to_bytes()
	var first = true
	var remaining = full.clone()
	var element = empty()
	var more = true

	while more {
		slash := remaining.index_of_byte(47, 0)
		more = slash != null
		element = sub(remaining, 0, slash or remaining.length())
		remaining = sub(remaining, (slash or - 1) + 1, remaining.length())

		if dot_count(element) == 1 {
			first = false
		} else if dot_count(element) == 2 {
			last := last_index(sub(dst, 1, dst.length()), 47)
			dst = sub(dst, 0, if last >= 0 { last + 1 } else { 1 })
			if last < 0 { first = true }
		} else {
			if not first { dst = dst.concat("/".to_bytes()) }
			dst = dst.concat(element)
			first = false
		}
	}

	if dot_count(element) > 0 {
		dst = dst.concat("/".to_bytes())
	}
	return if dst.length() > 1 and dst.get(1).to_int() == 47 { sub(dst, 1, dst.length()) } else { dst }
}

fn set_resolved(var url Parts, base, reference Bytes) Void {
	set_path(url, resolve_path(base, reference))
}

fn clear_authority(var url Parts) Void {
	url.has_user = false
	url.password_set = false
	url.username = empty()
	url.password = empty()
	url.host = empty()
	url.path = empty()
}

fn copy_parts(p Parts) Parts {
	return Parts(
		p.scheme.clone(),
		p.opaque.clone(),
		p.host.clone(),
		p.path.clone(),
		p.raw_path.clone(),
		p.raw_query.clone(),
		p.fragment.clone(),
		p.raw_fragment.clone(),
		p.username.clone(),
		p.password.clone(),
		p.has_user,
		p.password_set,
		p.omit_host,
		p.force_query,
	)
}

// Go's ResolveReference.
fn resolve_reference(base, r Parts) Parts {
	var url = copy_parts(r)
	reference_path := escaped_path(r)
	if r.scheme.is_empty() { url.scheme = base.scheme.clone() }

	if not r.scheme.is_empty() or not r.host.is_empty() or r.has_user {
		set_resolved(url, reference_path, empty())
	} else if not r.opaque.is_empty() {
		clear_authority(url)
	} else {
		if r.path.is_empty() and not r.force_query and r.raw_query.is_empty() {
			url.raw_query = base.raw_query.clone()

			if r.fragment.is_empty() {
				url.fragment = base.fragment.clone()
				url.raw_fragment = base.raw_fragment.clone()
			}
		}

		if r.path.is_empty() and not base.opaque.is_empty() {
			url.opaque = base.opaque.clone()
			clear_authority(url)
		} else {
			url.host = base.host.clone()
			url.has_user = base.has_user
			url.password_set = base.password_set
			url.username = base.username.clone()
			url.password = base.password.clone()
			set_resolved(url, escaped_path(base), reference_path)
		}
	}

	return url
}

type HostPort {
	name, port Bytes
}

// Splits `host:port` (the port is empty when there is none) and strips the brackets of
// an IP literal.
fn split_host_port(host_port Bytes) HostPort {
	var name = host_port.clone()
	var port = empty()
	colon := last_index(host_port, 58)

	if colon >= 0 and valid_optional_port(host_port.view(colon, host_port.length())) {
		port = sub(host_port, colon + 1, host_port.length())
		name = sub(host_port, 0, colon)
	}

	if (
		name.length() >= 2
		and name.get(0).to_int() == 91
		and name.get(name.length() - 1).to_int() == 93
	) {
		name = sub(name, 1, name.length() - 1)
	}
	return HostPort(name, port)
}

fn valid_query(query Bytes) Bool {
	for i in 0..query.length() {
		c := query.get(i).to_int()
		if c == 35 or c == 32 or c < 32 or c == 127 { return false }
		if (
			c == 37
			and (
				i + 2 >= query.length()
				or hex_value(query.get(i + 1).to_int()) < 0
				or hex_value(query.get(i + 2).to_int()) < 0
			)
		) { return false }
	}

	return true
}

// The width of the UTF-8 sequence a lead byte starts, or 0.
fn sequence_width(lead Int) Int {
	if lead >= 194 and lead <= 223 { return 2 }
	if lead >= 224 and lead <= 239 { return 3 }
	if lead >= 240 and lead <= 244 { return 4 }

	return 0
}

// Go's strings.ToLower for text that may hold invalid UTF-8: each bad byte becomes
// U+FFFD, and each scalar takes its first lowercase scalar.
fn go_lower(data Bytes) Bytes {
	var out = BytesBuilder()
	var i = 0

	while i < data.length() {
		c := data.get(i).to_int()
		width := if c < 128 { 1 } else { sequence_width(c) }
		scalar := if width > 1 and i + width <= data.length() {
			data.decode_utf8_range(i, i + width)
		} else {
			null
		}

		if c < 128 {
			out.append((if c >= 65 and c <= 90 { c + 32 } else { c }).to_uint8() or 0)
		} else if scalar != null {
			out.append_bytes(scalar.lower().chars()[0].to_bytes())
		} else {
			out.append_bytes("\u{FFFD}".to_bytes())
			width = 1
		}

		i += width
	}

	return out.build()
}

// Lowercases a hostname but keeps an IPv6 zone identifier (after the first `%`), which
// is case-sensitive.
fn go_lower_host(host Bytes) Bytes {
	percent := host.index_of_byte(37, 0) or host.length()
	return go_lower(sub(host, 0, percent)).concat(sub(host, percent, host.length()))
}

// The record for `parts`, or EBADMSG for user information, an opaque URL, no scheme, a
// bad port or bad text.
fn components(parts Parts) Url! {
	if parts.has_user or not parts.opaque.is_empty() or parts.scheme.is_empty() { return invalid_data() }

	split := split_host_port(parts.host)
	var port = 0

	for i in 0..split.port.length() {
		port = port * 10 + split.port.get(i).to_int() - 48
		if port > 65535 { return invalid_data() }
	}

	bracketed := starts_with(parts.host, "[")
	if parts.path.decode_utf8() == null or not valid_query(parts.raw_query) { return invalid_data() }
	if split.name.index_of_byte(
		58,
		0,
	) != null and not bracketed { return invalid_data() }

	path := text_of(escaped_path(parts))?
	fragment := text_of(parts.fragment)?
	host := text_of(go_lower_host(split.name))?
	scheme := text_of(lower_ascii(parts.scheme))?
	var query String? = null
	if parts.force_query or not parts.raw_query.is_empty() {
		query = text_of(parts.raw_query)?
	}

	var number Int? = null
	if not split.port.is_empty() { number = port }
	return ok(Url(scheme, host, path, fragment, query, number, parts.omit_host))
}

// The `Parts` of a record once its cheap checks pass (Go's JoinHostPort, path unescape,
// query and host validity); null rejects it.
fn build_parts(v Url, var url Parts) Bool {
	host := v.host.to_bytes()
	var joined = if host.index_of_byte(58, 0) != null {
		"[".to_bytes().concat(host).concat("]".to_bytes())
	} else {
		host
	}
	port := v.port

	if port != null {
		if port < 0 or port > 65535 { return false }

		joined = joined.concat(":".to_bytes()).concat(port.to_string().to_bytes())
	}

	raw := v.path.to_bytes()
	if joined.is_empty() and not raw.is_empty() and raw.get(
		0
	).to_int() != 47 { return false }

	path := unescape(raw, 1)
	if path == null or path.decode_utf8() == null { return false }

	address := sub(joined, 0, joined.index_of_byte(37, 0) or joined.length())
	query := (v.query or "").to_bytes()
	if not valid_query(query) { return false }
	if (
		address.index_of_byte(32, 0) != null
		or address.index_of_byte(60, 0) != null
		or address.index_of_byte(62, 0) != null
		or address.index_of_byte(34, 0) != null
	) { return false }

	url.scheme = v.scheme.to_bytes()
	url.host = joined
	url.path = path
	url.raw_path = raw
	url.force_query = v.query != null and query.is_empty()
	url.raw_query = query
	url.fragment = v.fragment.to_bytes()
	url.omit_host = v.omit_host
	return true
}

fn scheme_byte(c Int) Bool {
	return is_alnum(c) or c == 43 or c == 45 or c == 46
}

fn name_byte(c Int) Bool {
	return is_alnum(c) or c == 45 or c == 46 or c == 95 or c == 126
}

// Whether every byte of `data` is a scheme byte (`name` false) or a plain host-name
// byte (`name` true).
fn all_bytes(data Bytes, name Bool) Bool {
	for i in 0..data.length() {
		c := data.get(i).to_int()
		if not (if name { name_byte(c) } else { scheme_byte(c) }) { return false }
	}

	return true
}

// Whether rendering `u` is known to read back as a URL with the same scheme and no user
// information, without parsing it: a valid scheme, a plain host name, and a path that
// cannot be re-read as an authority.
fn reads_back_plain(u Parts) Bool {
	scheme_ok := (
		not u.scheme.is_empty()
		and is_alpha(u.scheme.get(0).to_int())
		and all_bytes(u.scheme, false)
	)
	plain_host := (
		not starts_with(u.host, "[")
		and all_bytes(split_host_port(u.host).name, true)
	)
	rereads_path := (
		u.host.is_empty()
		and (starts_with(u.path, "//") or starts_with(u.raw_path, "//"))
	)
	return scheme_ok and plain_host and not rereads_path
}

// The reference check: parse what was rendered and require a hierarchical URL with the
// same scheme, no user information and no host byte that would change the authority.
fn reparses(u Parts, rendered Bytes) Bool {
	parsed := parse_parts(rendered)
	if parsed == null { return false }
	if parsed.scheme.is_empty() or lower_ascii(parsed.scheme) != lower_ascii(u.scheme) { return false }
	if not parsed.opaque.is_empty() or parsed.has_user { return false }

	for i in 0..u.host.length() {
		c := u.host.get(i).to_int()
		if c == 47 or c == 64 or c == 92 or c == 13 or c == 10 { return false }
	}

	return true
}

// Rebuilds a URL from `v` into `parts` and returns its text, rejecting anything that
// would not parse back.
fn go_url(v Url, var parts Parts) Bytes? {
	if not build_parts(v, parts) { return null }

	text := render(parts)
	if not reads_back_plain(parts) and not reparses(parts, text) { return null }

	return text
}

// Decodes one percent-encoded URL component. `+` is not treated as a space.
export fn decode_component(text String) String! {
	data := text.to_bytes()
	var out = BytesBuilder()
	var i = 0

	while i < data.length() {
		c := data.get(i).to_int()

		if c != 37 {
			out.append(c.to_uint8() or 0)
			i += 1
			continue
		}

		if i + 2 >= data.length() { return invalid_data() }

		high := hex_value(data.get(i + 1).to_int())
		low := hex_value(data.get(i + 2).to_int())
		if high < 0 or low < 0 { return invalid_data() }

		out.append((high * 16 + low).to_uint8() or 0)
		i += 3
	}

	return text_of(out.build())
}

// Percent-encodes one URL component using UTF-8 bytes.
export fn encode_component(text String) String {
	data := text.to_bytes()
	var out = BytesBuilder()

	for i in 0..data.length() {
		c := data.get(i).to_int()

		if is_alnum(c) or c == 45 or c == 46 or c == 95 or c == 126 {
			out.append(c.to_uint8() or 0)
		} else {
			out.append(37)
			out.append(hex_digit(c / 16))
			out.append(hex_digit(c % 16))
		}
	}

	return out.build().decode_utf8() or ""
}

// Formats URL components as an absolute hierarchical URL. Missing or malformed schemes
// and hostless relative paths return EINVAL, as do other invalid components.
export fn format(value Url) String! {
	var parts = new_parts()
	text := go_url(value, parts)
	if text == null { return invalid_input() }

	// A bare scheme would read as an opaque URL, so an empty hierarchical part keeps
	// `//` unless the URL was read without one.
	if parts.host.is_empty() and parts.path.is_empty() and not parts.omit_host {
		at := parts.scheme.length() + 1
		return text_of(
			sub(text, 0, at).concat("//".to_bytes()).concat(
				sub(text, at, text.length())
			)
		)
	}

	return text_of(text)
}

// Encodes query entries as a query string.
export fn format_query(entries List[QueryEntry]) String {
	var out = BytesBuilder()

	for index in 0..entries.length() {
		if index > 0 {
			out.append(38)
		}
		out.append_bytes(escape(entries[index].key.to_bytes(), 5))
		out.append(61)
		out.append_bytes(escape(entries[index].value.to_bytes(), 5))
	}

	return out.build().decode_utf8() or ""
}

// Parses an absolute URL into its components.
export fn parse(text String) Url! {
	parts := parse_parts(text.view_bytes())
	if parts == null or parts.scheme.is_empty() or parts.has_user { return invalid_data() }

	return components(parts)
}

// Parses a query string, preserving duplicate keys and their input order.
export fn parse_query(text String, max_entries Int?) List[QueryEntry]! {
	limit := max_entries
	if limit != null and limit < 0 { return invalid_input() }

	data := text.to_bytes()
	var entries = List[QueryEntry]()
	var start = 0

	while start < data.length() {
		stop := data.index_of_byte(38, start) or data.length()

		if stop > start {
			if limit != null and entries.length() >= limit {
				return error(Error("URL: limit exceeded", kind: "EOVERFLOW"))
			}

			entry := query_entry(data, start, stop)
			if entry == null { return invalid_data() }

			entries.append(entry)
		}

		start = stop + 1
	}

	return ok(entries)
}

// Resolves a relative reference against a base URL.
export fn resolve(base Url, reference String) Url! {
	var built = new_parts()
	if go_url(base, built) == null { return invalid_input() }

	parsed := parse_parts(reference.view_bytes())
	if parsed == null or parsed.has_user { return invalid_data() }

	return components(resolve_reference(built, parsed))
}
