// conform: tags=control-flow,formatter,interpolation,match,modules,parser,stdlib-archive,stdlib-binary,stdlib-bytes,stdlib-compress,stdlib-crypto,stdlib-encoding,stdlib-json,stdlib-math,stdlib-string,stdlib-testing,stdlib-url,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/library.ms
import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	sha256 from "@std/crypto/crypto.ms",
	base64_decode, hex_decode, hex_encode from "@std/data/encoding.ms",
	JsonOptions, JsonValue, parse, stringify from "@std/data/json.ms",
	ArchiveEntry,
	ArchiveOptions,
	compress,
	decompress,
	pack,
	unpack from "@std/io/archive.ms",
	round, sqrt from "@std/math/math.ms",
	format_query, parse_query from "@std/net/url.ms",
	from_scalars from "@std/string.ms",
	expect_equal, expect_false, fail from "@std/test/test.ms",
)

fn twice(value Int) Int {
	return value * 2
}

fn positive(value Int) Bool {
	return value > 0
}

fn sum(accumulator Int, value Int) Int {
	return accumulator + value
}

fn compare(left Int, right Int) Int {
	if left < right {
		return -1
	}
	if left > right {
		return 1
	}

	return 0
}

fn verify_json() Void! {
	limits := JsonOptions(max_bytes: 1024, max_depth: 8, max_values: 32)
	value := parse(text: "{\"large\":9007199254740993,\"ok\":true}", limits: limits)?
	(
		(
			not (
				stringify(
					value: value,
					max_bytes: 1024,
				)? == "{\"large\":9007199254740993,\"ok\":true}"
			)
		)
		| expect_false?
	)
}

fn verify_encoding() Void! {
	bytes := hex_decode(text: "00ff42", max_bytes: 3)?
	hex_encode(data: bytes) | expect_equal("00ff42")?
	(
		(
			not (
				hex_encode(
					data: sha256(data: "abc".to_bytes())
				) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
			)
		)
		| expect_false?
	)
}

fn verify_url() Void! {
	query := parse_query(text: "a=1&a=2&space=hello+world", max_entries: 3)?
	query.length() | expect_equal(3)?
	format_query(entries: query) | expect_equal("a=1&a=2&space=hello+world")?
}

fn verify_binary() Void! {
	var out = BytesBuilder()
	out.append_int16_be(-32768)
	(out.build().int16_be(0)?).to_int() | expect_equal(-32768)?
}

fn verify_compression() Void! {
	compressed := compress(
		data: "hello hello hello".to_bytes(),
		format: "gzip",
		level: 6,
		max_bytes: 256,
	)?
	(
		(
			not (
				decompress(
					data: compressed,
					format: "gzip",
					max_bytes: 17,
				)? == "hello hello hello".to_bytes()
			)
		)
		| expect_false?
	)
}

fn verify_archive() Void! {
	entries := [
		ArchiveEntry(
			path: "hello.txt",
			data: "hello".to_bytes(),
			directory: false,
		)
	]
	archive := pack(entries: entries, format: "zip", max_bytes: 1024)?
	(
		(
			not (
				unpack(
					data: archive,
					format: "zip",
					limits: ArchiveOptions(
						max_entries: 1,
						max_entry_bytes: 5,
						max_bytes: 5,
					),
				)? == entries
			)
		)
		| expect_false?
	)
}

test "expanded packages run through compiler" {
	match verify_json() {
		ok(_) => {
			_verified := void
		}
		error(_) => {
			return fail(message: "json failed")
		}
	}

	match verify_encoding() {
		ok(_) => {
			_verified := void
		}
		error(_) => {
			return fail(message: "encoding failed")
		}
	}

	match verify_url() {
		ok(_) => {
			_verified := void
		}
		error(_) => {
			return fail(message: "url failed")
		}
	}

	match verify_binary() {
		ok(_) => {
			_verified := void
		}
		error(_) => {
			return fail(message: "binary failed")
		}
	}

	match verify_compression() {
		ok(_) => {
			_verified := void
		}
		error(_) => {
			return fail(message: "compression failed")
		}
	}

	match verify_archive() {
		ok(_) => {
			_verified := void
		}
		error(_) => {
			return fail(message: "archive failed")
		}
	}
	("a,,b").split(separator: ",") | expect_equal(["a", "", "b"])?
	("é🙂").scalar_length() | expect_equal(2)?
	("é").scalar_values() | expect_equal([233])?

	text_success String! := ok("é")
	from_scalars(values: [233]) | expect_equal(text_success)?
	sqrt(value: 9.0) | expect_equal(3.0)?
	round(value: 2.5) | expect_equal(3.0)?
	([1, 2]).map(transform: twice) | expect_equal([2, 4])?
	([-1, 3, 0, 2]).filter(predicate: positive) | expect_equal([3, 2])?
	([1, 2, 3]).fold(initial: 0, step: sum) | expect_equal(6)?
	([3, 1, 2]).sorted(compare: compare) | expect_equal([1, 2, 3])?

	var flipped = [1, 2]
	flipped.reverse()
	flipped | expect_equal([2, 1])?
}

test "malformed and bounded inputs return errors" {
	failure1 Bytes! := error(Error("encoding: invalid data", kind: "EBADMSG"))
	(
		base64_decode(
			text: "Zh==",
			url_safe: false,
			max_bytes: 10,
		) | expect_equal(failure1)?
	)

	failure2 Bytes! := error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
	hex_decode(text: "abcd", max_bytes: 1) | expect_equal(failure2)?

	limits := JsonOptions(max_bytes: 100, max_depth: 2, max_values: 10)
	failure3 := parse(text: "{\"a\":1,\"a\":2}", limits: limits)
	(
		failure3.err().message | expect_equal(
			"JSON: invalid data: line 1, column 14: duplicate object key"
		)?
	)

	failure4 JsonValue! := error(Error("JSON: limit exceeded", kind: "EOVERFLOW"))
	parse(text: "[[[]]]", limits: limits) | expect_equal(failure4)?
}
// expect-format: rewritten
// expect-formatted: import (
// expect-formatted: \tBytes, BytesBuilder from "@std/bytes.ms",
// expect-formatted: \tsha256 from "@std/crypto/crypto.ms",
// expect-formatted: \tbase64_decode, hex_decode, hex_encode from "@std/data/encoding.ms",
// expect-formatted: \tJsonOptions, JsonValue, parse, stringify from "@std/data/json.ms",
// expect-formatted: \tArchiveEntry,
// expect-formatted: \tArchiveOptions,
// expect-formatted: \tcompress,
// expect-formatted: \tdecompress,
// expect-formatted: \tpack,
// expect-formatted: \tunpack from "@std/io/archive.ms",
// expect-formatted: \tround, sqrt from "@std/math/math.ms",
// expect-formatted: \tformat_query, parse_query from "@std/net/url.ms",
// expect-formatted: \tfrom_scalars from "@std/string.ms",
// expect-formatted: \texpect_equal, expect_false, fail from "@std/test/test.ms",
// expect-formatted: )
// expect-formatted:
// expect-formatted: fn twice(value Int) Int {
// expect-formatted: \treturn value * 2
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn positive(value Int) Bool {
// expect-formatted: \treturn value > 0
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn sum(accumulator, value Int) Int {
// expect-formatted: \treturn accumulator + value
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn compare(left, right Int) Int {
// expect-formatted: \tif left < right {
// expect-formatted: \t\treturn -1
// expect-formatted: \t}
// expect-formatted: \tif left > right {
// expect-formatted: \t\treturn 1
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treturn 0
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn verify_json() Void! {
// expect-formatted: \tlimits := JsonOptions(max_bytes: 1024, max_depth: 8, max_values: 32)
// expect-formatted: \tvalue := parse(text: "{\\"large\\":9007199254740993,\\"ok\\":true}", limits: limits)?
// expect-formatted: \t(
// expect-formatted: \t\t(
// expect-formatted: \t\t\tnot (
// expect-formatted: \t\t\t\tstringify(
// expect-formatted: \t\t\t\t\tvalue: value,
// expect-formatted: \t\t\t\t\tmax_bytes: 1024,
// expect-formatted: \t\t\t\t)? == "{\\"large\\":9007199254740993,\\"ok\\":true}"
// expect-formatted: \t\t\t)
// expect-formatted: \t\t)
// expect-formatted: \t\t| expect_false?
// expect-formatted: \t)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn verify_encoding() Void! {
// expect-formatted: \tbytes := hex_decode(text: "00ff42", max_bytes: 3)?
// expect-formatted: \thex_encode(data: bytes) | expect_equal("00ff42")?
// expect-formatted: \t(
// expect-formatted: \t\t(
// expect-formatted: \t\t\tnot (
// expect-formatted: \t\t\t\thex_encode(
// expect-formatted: \t\t\t\t\tdata: sha256(data: "abc".to_bytes())
// expect-formatted: \t\t\t\t) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
// expect-formatted: \t\t\t)
// expect-formatted: \t\t)
// expect-formatted: \t\t| expect_false?
// expect-formatted: \t)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn verify_url() Void! {
// expect-formatted: \tquery := parse_query(text: "a=1&a=2&space=hello+world", max_entries: 3)?
// expect-formatted: \tquery.length() | expect_equal(3)?
// expect-formatted: \tformat_query(entries: query) | expect_equal("a=1&a=2&space=hello+world")?
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn verify_binary() Void! {
// expect-formatted: \tvar out = BytesBuilder()
// expect-formatted: \tout.append_int16_be(-32768)
// expect-formatted: \t(out.build().int16_be(0)?).to_int() | expect_equal(-32768)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn verify_compression() Void! {
// expect-formatted: \tcompressed := compress(
// expect-formatted: \t\tdata: "hello hello hello".to_bytes(),
// expect-formatted: \t\tformat: "gzip",
// expect-formatted: \t\tlevel: 6,
// expect-formatted: \t\tmax_bytes: 256,
// expect-formatted: \t)?
// expect-formatted: \t(
// expect-formatted: \t\t(
// expect-formatted: \t\t\tnot (
// expect-formatted: \t\t\t\tdecompress(
// expect-formatted: \t\t\t\t\tdata: compressed,
// expect-formatted: \t\t\t\t\tformat: "gzip",
// expect-formatted: \t\t\t\t\tmax_bytes: 17,
// expect-formatted: \t\t\t\t)? == "hello hello hello".to_bytes()
// expect-formatted: \t\t\t)
// expect-formatted: \t\t)
// expect-formatted: \t\t| expect_false?
// expect-formatted: \t)
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn verify_archive() Void! {
// expect-formatted: \tentries := [
// expect-formatted: \t\tArchiveEntry(
// expect-formatted: \t\t\tpath: "hello.txt",
// expect-formatted: \t\t\tdata: "hello".to_bytes(),
// expect-formatted: \t\t\tdirectory: false,
// expect-formatted: \t\t)
// expect-formatted: \t]
// expect-formatted: \tarchive := pack(entries: entries, format: "zip", max_bytes: 1024)?
// expect-formatted: \t(
// expect-formatted: \t\t(
// expect-formatted: \t\t\tnot (
// expect-formatted: \t\t\t\tunpack(
// expect-formatted: \t\t\t\t\tdata: archive,
// expect-formatted: \t\t\t\t\tformat: "zip",
// expect-formatted: \t\t\t\t\tlimits: ArchiveOptions(
// expect-formatted: \t\t\t\t\t\tmax_entries: 1,
// expect-formatted: \t\t\t\t\t\tmax_entry_bytes: 5,
// expect-formatted: \t\t\t\t\t\tmax_bytes: 5,
// expect-formatted: \t\t\t\t\t),
// expect-formatted: \t\t\t\t)? == entries
// expect-formatted: \t\t\t)
// expect-formatted: \t\t)
// expect-formatted: \t\t| expect_false?
// expect-formatted: \t)
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "expanded packages run through compiler" {
// expect-formatted: \tmatch verify_json() {
// expect-formatted: \t\tok(_) => {
// expect-formatted: \t\t\t_verified := void
// expect-formatted: \t\t}
// expect-formatted: \t\terror(_) => {
// expect-formatted: \t\t\treturn fail(message: "json failed")
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tmatch verify_encoding() {
// expect-formatted: \t\tok(_) => {
// expect-formatted: \t\t\t_verified := void
// expect-formatted: \t\t}
// expect-formatted: \t\terror(_) => {
// expect-formatted: \t\t\treturn fail(message: "encoding failed")
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tmatch verify_url() {
// expect-formatted: \t\tok(_) => {
// expect-formatted: \t\t\t_verified := void
// expect-formatted: \t\t}
// expect-formatted: \t\terror(_) => {
// expect-formatted: \t\t\treturn fail(message: "url failed")
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tmatch verify_binary() {
// expect-formatted: \t\tok(_) => {
// expect-formatted: \t\t\t_verified := void
// expect-formatted: \t\t}
// expect-formatted: \t\terror(_) => {
// expect-formatted: \t\t\treturn fail(message: "binary failed")
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tmatch verify_compression() {
// expect-formatted: \t\tok(_) => {
// expect-formatted: \t\t\t_verified := void
// expect-formatted: \t\t}
// expect-formatted: \t\terror(_) => {
// expect-formatted: \t\t\treturn fail(message: "compression failed")
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \tmatch verify_archive() {
// expect-formatted: \t\tok(_) => {
// expect-formatted: \t\t\t_verified := void
// expect-formatted: \t\t}
// expect-formatted: \t\terror(_) => {
// expect-formatted: \t\t\treturn fail(message: "archive failed")
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \t("a,,b").split(separator: ",") | expect_equal(["a", "", "b"])?
// expect-formatted: \t("é🙂").scalar_length() | expect_equal(2)?
// expect-formatted: \t("é").scalar_values() | expect_equal([233])?
// expect-formatted:
// expect-formatted: \ttext_success String! := ok("é")
// expect-formatted: \tfrom_scalars(values: [233]) | expect_equal(text_success)?
// expect-formatted: \tsqrt(value: 9.0) | expect_equal(3.0)?
// expect-formatted: \tround(value: 2.5) | expect_equal(3.0)?
// expect-formatted: \t([1, 2]).map(transform: twice) | expect_equal([2, 4])?
// expect-formatted: \t([-1, 3, 0, 2]).filter(predicate: positive) | expect_equal([3, 2])?
// expect-formatted: \t([1, 2, 3]).fold(initial: 0, step: sum) | expect_equal(6)?
// expect-formatted: \t([3, 1, 2]).sorted(compare: compare) | expect_equal([1, 2, 3])?
// expect-formatted:
// expect-formatted: \tvar flipped = [1, 2]
// expect-formatted: \tflipped.reverse()
// expect-formatted: \tflipped | expect_equal([2, 1])?
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "malformed and bounded inputs return errors" {
// expect-formatted: \tfailure1 Bytes! := error(Error("encoding: invalid data", kind: "EBADMSG"))
// expect-formatted: \t(
// expect-formatted: \t\tbase64_decode(
// expect-formatted: \t\t\ttext: "Zh==",
// expect-formatted: \t\t\turl_safe: false,
// expect-formatted: \t\t\tmax_bytes: 10,
// expect-formatted: \t\t) | expect_equal(failure1)?
// expect-formatted: \t)
// expect-formatted:
// expect-formatted: \tfailure2 Bytes! := error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
// expect-formatted: \thex_decode(text: "abcd", max_bytes: 1) | expect_equal(failure2)?
// expect-formatted:
// expect-formatted: \tlimits := JsonOptions(max_bytes: 100, max_depth: 2, max_values: 10)
// expect-formatted: \tfailure3 := parse(text: "{\\"a\\":1,\\"a\\":2}", limits: limits)
// expect-formatted: \t(
// expect-formatted: \t\tfailure3.err().message | expect_equal(
// expect-formatted: \t\t\t"JSON: invalid data: line 1, column 14: duplicate object key"
// expect-formatted: \t\t)?
// expect-formatted: \t)
// expect-formatted:
// expect-formatted: \tfailure4 JsonValue! := error(Error("JSON: limit exceeded", kind: "EOVERFLOW"))
// expect-formatted: \tparse(text: "[[[]]]", limits: limits) | expect_equal(failure4)?
// expect-formatted: }
