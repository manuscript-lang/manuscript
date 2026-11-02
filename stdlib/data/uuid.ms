import Bytes, BytesBuilder from "@std/bytes.ms"
import hex_encode, hex_decode from "@std/data/encoding.ms"
import HashAlgorithm from "@std/crypto.ms"
import bit_and, bit_or, shift_right_unsigned from "@std/math/math.ms"
import random_bytes, RandomError from "@std/os/random.ms"
import now from "@std/os/time.ms"

# Errors returned when UUID text is malformed.
export type UuidError:
    # The text is not 36 characters of the form `8-4-4-4-12` hexadecimal digits.
    case InvalidData

impl Error for UuidError:
    # Returns the fixed diagnostic `uuid: invalid data`.
    fn message() String:
        match self:
            InvalidData: return "uuid: invalid data"

# The namespace for fully qualified domain names, for `uuid_v5`.
export let namespace_dns = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
# The namespace for URLs, for `uuid_v5`.
export let namespace_url = "6ba7b811-9dad-11d1-80b4-00c04fd430c8"
# The namespace for ISO object identifiers, for `uuid_v5`.
export let namespace_oid = "6ba7b812-9dad-11d1-80b4-00c04fd430c8"
# The namespace for X.500 distinguished names, for `uuid_v5`.
export let namespace_x500 = "6ba7b814-9dad-11d1-80b4-00c04fd430c8"

# Creates the version-5 (SHA-1, name-based) UUID of `name` within `namespace`.
# The same namespace and name always give the same lowercase UUID, so it makes a stable id for a URL, a path or a key.
# `namespace` is any UUID text, such as `namespace_url` or an application's own UUID; malformed text returns InvalidData.
# Example: `uuid_v5(namespace_dns, "python.org")` is `"886313e1-3b8a-5372-9b90-0c9aee199e5d"`.
export fn uuid_v5(namespace: String, name: String) String!UuidError:
    let space = try uuid_to_bytes(namespace)
    var input = BytesBuilder()
    input.append_bytes(space)
    input.append_bytes(name.to_bytes())

    let digest = HashAlgorithm.Sha1.digest(input.build())
    return ok(format_uuid(digest, 5))

# Creates a version-7 UUID: the current Unix time in milliseconds followed by random bits, in lowercase text.
# Ids made later sort after ids made earlier as strings, which keeps database indexes and logs in creation order.
# Two ids made in the same millisecond are ordered randomly. Entropy failures return RandomError.
export fn uuid_v7() String!RandomError:
    let moment = now()
    let millis = moment.seconds * 1000 + moment.nanos / 1000000
    let noise = try random_bytes(10)
    var raw = BytesBuilder()
    for place in 0..6:
        raw.append(
            bit_and(
                shift_right_unsigned(millis, 8 * (5 - place)), 255
            ).to_uint8().get(0)
        )
    raw.append_bytes(noise)
    return ok(format_uuid(raw.build(), 7))

# Returns the version digit (1 through 8) of an RFC 9562 UUID text, or none when `text` is not a UUID of that variant.
# Case does not matter. Example: `uuid_version("886313e1-3b8a-5372-9b90-0c9aee199e5d")` is `5`.
export fn uuid_version(text: String) Int?:
    let raw = uuid_to_bytes(text)

    if let bytes = raw:
        let version = shift_right_unsigned(bytes.get(6).to_int(), 4)
        let variant = shift_right_unsigned(bytes.get(8).to_int(), 6)
        if variant == 2 and version >= 1 and version <= 8: return version

    return none

# Parses the 16 bytes of a UUID text of any version.
fn uuid_to_bytes(text: String) Bytes!UuidError:
    if text.length() != 36: return error(UuidError.InvalidData)

    let groups = text.split("-")
    if groups.length() != 5: return error(UuidError.InvalidData)
    if groups[0].length() != 8 or groups[1].length() != 4 or groups[2].length() != 4:
        return error(UuidError.InvalidData)
    if groups[3].length() != 4 or groups[4].length() != 12:
        return error(UuidError.InvalidData)

    let decoded = hex_decode(text.replace("-", ""), 16)
    if let bytes = decoded:
        return ok(bytes)

    return error(UuidError.InvalidData)

# Stamps the version and RFC 9562 variant onto the first 16 bytes and renders them as lowercase `8-4-4-4-12` text.
fn format_uuid(source: Bytes, version: Int) String:
    var raw = BytesBuilder()

    for place in 0..16:
        var byte = source.get(place).to_int()
        if place == 6: byte = bit_or(bit_and(byte, 15), version * 16)
        if place == 8: byte = bit_or(bit_and(byte, 63), 128)
        raw.append(byte.to_uint8().get(0))

    let hex = hex_encode(raw.build())
    return "{hex.take(8)}-{hex.drop(8).take(4)}-{hex.drop(12).take(4)}-{hex.drop(16).take(4)}-{hex.drop(20)}"
