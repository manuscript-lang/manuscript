import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	HashAlgorithm from "@std/crypto/crypto.ms",
	hex_decode, hex_encode from "@std/data/encoding.ms",
	bit_and, bit_or, shift_right_unsigned from "@std/math/math.ms",
	random_bytes from "@std/random.ms",
	now from "@std/time.ms",

	draw_uuid, msstd_random_v7_next from "@std/internal/random.ms",
)

// The namespace for fully qualified domain names, for `uuid_v5`.
export namespace_dns := "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
// The namespace for URLs, for `uuid_v5`.
export namespace_url := "6ba7b811-9dad-11d1-80b4-00c04fd430c8"
// The namespace for ISO object identifiers, for `uuid_v5`.
export namespace_oid := "6ba7b812-9dad-11d1-80b4-00c04fd430c8"
// The namespace for X.500 distinguished names, for `uuid_v5`.
export namespace_x500 := "6ba7b814-9dad-11d1-80b4-00c04fd430c8"

// Creates a random version-4 UUID in lowercase text from the operating system's
// entropy. Entropy failures return an `Error`.
// ms: effect std.random.read
export fn uuid_v4() String!:
	return draw_uuid()

/*
Creates the version-5 (SHA-1, name-based) UUID of `name` within `namespace`.
The same namespace and name always give the same lowercase UUID, so it makes a stable id for a URL, a path or a key.
`namespace` is any UUID text, such as `namespace_url` or an application's own UUID; malformed text returns an `Error` with kind `EBADMSG`.
Example: `uuid_v5(namespace_dns, "python.org")` is `"886313e1-3b8a-5372-9b90-0c9aee199e5d"`.
*/
export fn uuid_v5(namespace: String, name: String) String!:
	space := uuid_to_bytes(namespace)?
	var input = BytesBuilder()
	input.append_bytes(space)
	input.append_bytes(name.to_bytes())

	digest := HashAlgorithm.Sha1.digest(input.build())
	return ok(format_uuid(digest, 5))

/*
Creates a version-7 UUID: the current Unix time in milliseconds, a 12-bit sequence, then random bits, in lowercase text.
Ids made later sort after ids made earlier as strings, which keeps database indexes and logs in creation order.
Ids made in the same millisecond, even by different tasks, are ordered by the sequence, which counts up from a random start; if the sequence fills up or the clock steps back, the timestamp field keeps counting forward instead. Entropy failures return an `Error`.
*/
export fn uuid_v7() String!:
	moment := now()
	millis := moment.seconds * 1000 + moment.nanos / 1000000
	noise := random_bytes(10)?
	stamp := msstd_random_v7_next(
		millis,
		noise.get(0).to_int() * 256 + noise.get(1).to_int(),
	)
	time := shift_right_unsigned(stamp, 12)
	sequence := bit_and(stamp, 4095)
	var raw = BytesBuilder()
	for place in 0..6:
		raw.append(
			bit_and(
				shift_right_unsigned(time, 8 * (5 - place)),
				255,
			).to_uint8() or 0
		)
	raw.append(shift_right_unsigned(sequence, 8).to_uint8() or 0)
	raw.append(bit_and(sequence, 255).to_uint8() or 0)
	for place in 2..10:
		raw.append(noise.get(place))
	return ok(format_uuid(raw.build(), 7))

// Returns the version digit (1 through 8) of a UUID text, or null when `text` is not an
// RFC 9562 UUID (including malformed text). Case does not matter. Example:
// `uuid_version("886313e1-3b8a-5372-9b90-0c9aee199e5d")` is `5`.
export fn uuid_version(text: String) Int?:
	raw := uuid_to_bytes(text)

	if bytes := raw:
		version := shift_right_unsigned(bytes.get(6).to_int(), 4)
		variant := shift_right_unsigned(bytes.get(8).to_int(), 6)
		if variant == 2 and version >= 1 and version <= 8: return version

	return null

// Parses the 16 bytes of a UUID text of any version.
fn uuid_to_bytes(text: String) Bytes!:
	if text.length() != 36: return error(Error("uuid: invalid data", kind: "EBADMSG"))

	groups := text.split("-")
	if groups.length() != 5: return error(Error("uuid: invalid data", kind: "EBADMSG"))
	if groups[0].length() != 8 or groups[1].length() != 4 or groups[2].length() != 4:
		return error(Error("uuid: invalid data", kind: "EBADMSG"))
	if groups[3].length() != 4 or groups[4].length() != 12:
		return error(Error("uuid: invalid data", kind: "EBADMSG"))

	decoded := hex_decode(text.replace("-", ""), 16)
	if bytes := decoded: return ok(bytes)

	return error(Error("uuid: invalid data", kind: "EBADMSG"))

// Stamps the version and RFC 9562 variant onto the first 16 bytes and renders them as
// lowercase `8-4-4-4-12` text.
fn format_uuid(source: Bytes, version: Int) String:
	var raw = BytesBuilder()

	for place in 0..16:
		var byte = source.get(place).to_int()
		if place == 6: byte = bit_or(bit_and(byte, 15), version * 16)
		if place == 8: byte = bit_or(bit_and(byte, 63), 128)
		raw.append(byte.to_uint8() or 0)

	hex := hex_encode(raw.build())
	return f"{hex.view(0, 8)}-{hex.view(8, 12)}-{hex.view(12, 16)}-{hex.view(16, 20)}-{hex.view(20, 32)}"
