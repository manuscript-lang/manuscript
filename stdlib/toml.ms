# TOML 1.0 parser implemented in Manuscript.
import parse_int, parse_float from "@std/math.ms"
import from_scalars, StringBuilder, Regex, compile from "@std/string.ms"
import Bytes from "@std/bytes.ms"
import log, sqrt from "@std/math.ms"

# A TOML value. Date and time values retain their original TOML text.
export type TomlValue:
    # Text decoded from TOML basic or literal string syntax.
    case StringValue(
        # Unicode contents after the applicable escapes and multiline rules.
        value: String
    )
    # A parsed whole number; out-of-range input is rejected rather than truncated.
    case IntValue(
        # Exact signed integer value of the accepted TOML numeric token.
        value: Int
    )
    # A parsed floating-point number, including TOML infinity and NaN spellings.
    case FloatValue(
        # Numeric value of the accepted floating token, preserving signed zero.
        value: Float
    )
    # A TOML true or false value; other capitalizations are invalid.
    case BoolValue(
        # The decoded boolean from the lowercase TOML token.
        value: Bool
    )
    # A validated local/offset date or time token, retained as text.
    case DateTimeValue(
        # Original accepted TOML date/time spelling, without a timezone conversion.
        text: String
    )
    # An ordered array; elements can have different TOML value kinds.
    case ArrayValue(
        # Element values in document order, with ordinary mutable list storage.
        values: List[TomlValue]
    )
    # An insertion-ordered table; parse returns this case even for an empty document.
    case TableValue(
        # String-keyed entries produced by assignments, dotted keys and table headers.
        values: Map[String, TomlValue]
    )

# Errors returned for invalid limits, malformed TOML, or exceeded resource bounds.
export type TomlError:
    # A supplied limit is negative, or stringify received a value that is not a table or holds a DateTimeValue that is not a valid TOML date or time.
    case InvalidInput
    # Invalid syntax, duplicate/conflicting keys, unsupported value forms or numeric range failures.
    case InvalidData(
        # One-based line of the invalid token or conflicting construct.
        line: Int,
        # One-based Unicode scalar column after CRLF normalization.
        column: Int,
        # Parser diagnostic describing the rejected TOML construct.
        reason: String
    )
    # Input, nesting or parsed/returned value counts exceed a supplied budget.
    case LimitExceeded

# Optional input-byte, nesting-depth, and parsed-value limits for TOML parsing.
# Fields left none add no budget. Calling `parse` without any limits applies depth 10,000 and 1,000,000 values; pass a `TomlLimits` to change that.
export type TomlLimits:
    # Maximum UTF-8 input bytes before CRLF normalization; none adds no budget.
    max_bytes: Optional[Int] = none
    # Maximum value depth, including scalar leaves and implicit tables, with the root at one.
    max_depth: Optional[Int] = none
    # Maximum containers and leaves, excluding keys; checked during parsing and materialization.
    max_values: Optional[Int] = none

impl Error for TomlError:
    # Formats the source line, scalar column and parser reason for a malformed document.
    fn message() String:
        match self:
            InvalidInput: return "invalid TOML input"
            InvalidData(line, column, reason): return "TOML {line}:{column}: {reason}"
            LimitExceeded: return "TOML limit exceeded"

# The document is read as UTF-8 bytes; `pos` is a byte offset and line/column are derived from it
# only when an error is reported.
type Reader:
    data: Bytes
    pos: Int
    limits: TomlLimits
    values: Int
    tables: List[Table]
    entries: List[Map[String, Node]]

# Table flags. A table's entries live at the same index of `Reader.entries`.
type Table:
    explicit: Bool
    dotted: Bool
    sealed: Bool

# Tables are stored in the reader and referenced by index, so a parent can name a child that
# later keys keep extending without two copies of the same table.
type Node:
    case Leaf(value: TomlValue)
    case TableNode(id: Int)
    case ArrayNode(values: List[Node])
    case TableArray(ids: List[Int])

fn new_table(var reader: Reader, explicit: Bool, dotted: Bool) Int:
    reader.tables.append(Table(explicit: explicit, dotted: dotted, sealed: false))
    reader.entries.append(Map[String, Node]())
    return reader.tables.length() - 1

fn flags(reader: Reader, id: Int) Table:
    return reader.tables.get(id)

fn store_flags(var reader: Reader, id: Int, flags: Table) Unit:
    reader.tables.set(id, flags)

fn lookup(reader: Reader, id: Int, key: String) Optional[Node]:
    return reader.entries.get(id).get(key)

fn contains_key(reader: Reader, id: Int, key: String) Bool:
    return reader.entries.get(id).contains(key)

# Adds an entry to the table's map in place.
fn put(var reader: Reader, id: Int, key: String, node: Node) Unit:
    reader.entries[id].add(key, node)

fn put_array(var reader: Reader, id: Int, key: String, ids: List[Int]) Unit:
    put(var reader, id, key, Node.TableArray(ids))

# Byte values the parser tests.
let TAB = 9
let NEWLINE = 10
let SPACE = 32
let DOUBLE_QUOTE = 34
let HASH = 35
let SINGLE_QUOTE = 39
let COMMA = 44
let DOT = 46
let EQUALS = 61
let LEFT_BRACKET = 91
let BACKSLASH = 92
let RIGHT_BRACKET = 93
let LEFT_BRACE = 123
let RIGHT_BRACE = 125

# The byte at `pos` as an Int, or -1 past either end of the document.
fn byte_at(data: Bytes, pos: Int) Int:
    if pos < 0 or pos >= data.length(): return -1

    return data.get(pos).to_int()

# The cursor as its own value, which stays valid while the reader moves.
fn cursor(reader: Reader) Int:
    return reader.pos

# The byte at the cursor, or -1 at the end of the document.
fn peek(reader: Reader) Int:
    return byte_at(reader.data, reader.pos)

fn ahead(reader: Reader, offset: Int) Int:
    return byte_at(reader.data, reader.pos + offset)

# Consumes one byte and returns it, or returns -1 without moving at the end.
fn advance(var reader: Reader) Int:
    let b = byte_at(reader.data, reader.pos)
    if b >= 0: reader.pos += 1
    return b

# The 1-based line and scalar column of the byte offset.
fn locate(data: Bytes, pos: Int) List[Int]:
    var line = 1
    var column = 1
    var index = 0

    while index < pos:
        let b = data.get(index).to_int()

        if b == NEWLINE:
            line += 1
            column = 1
        else if b < 128 or b >= 192:
            column += 1

        index += 1

    return [line, column]

fn invalid_at(reader: Reader, pos: Int, reason: String) TomlError:
    let place = locate(reader.data, pos)
    return TomlError.InvalidData(
        line: place.get(0), column: place.get(1), reason: reason
    )

fn invalid(reader: Reader, reason: String) TomlError:
    return invalid_at(reader, reader.pos, reason)

# The text between two byte offsets of the document.
fn slice_text(reader: Reader, start: Int, end: Int) String:
    return reader.data.slice(start, end).get().decode_utf8().get("")

fn space(var reader: Reader, multiline: Bool) Unit:
    var pos = cursor(reader)

    while true:
        var b = byte_at(reader.data, pos)

        if b == SPACE or b == TAB or (multiline and b == NEWLINE):
            pos += 1
        else if multiline and b == HASH:
            while b >= 0 and b != NEWLINE:
                pos += 1
                b = byte_at(reader.data, pos)
        else:
            break

    reader.pos = pos

# Limits applied when `parse` is called without any: deep nesting and alias expansion are
# the usual resource attacks. Pass a `TomlLimits` (even an empty one) to lift or change them.
fn default_limits() TomlLimits:
    return TomlLimits(max_depth: 10000, max_values: 1000000)

fn within(value: Int, limit: Optional[Int]) Bool:
    if let maximum = limit:
        return value <= maximum

    return true

fn allocate(var reader: Reader) Result[Unit, TomlError]:
    reader.values += 1
    if not within(reader.values, reader.limits.max_values): return error(
        TomlError.LimitExceeded
    )

    return ok(unit)

fn budget(reader: Reader, depth: Int) Result[Unit, TomlError]:
    if not within(depth, reader.limits.max_depth): return error(TomlError.LimitExceeded)

    return ok(unit)

# Whether a byte is a control character that a string may not contain unescaped.
fn string_control(b: Int, multiline: Bool) Bool:
    return (b < 32 and b != TAB and not (multiline and b == NEWLINE)) or b == 127

fn quote_char(quote: Int) String:
    if quote == DOUBLE_QUOTE: return "\""

    return "'"

# Basic and literal strings, including multiline delimiters and escaped newline folding.
fn string_value(var reader: Reader, key: Bool) Result[String, TomlError]:
    let quote = advance(var reader)
    var multiline = false

    if (not key and peek(reader) == quote and ahead(reader, 1) == quote):
        advance(var reader)
        advance(var reader)
        multiline = true
        if peek(reader) == NEWLINE: advance(var reader)

    # A single-line string without escapes is one slice of the document.
    if not multiline:
        var end = cursor(reader)
        var b = byte_at(reader.data, end)

        while (
            b != quote
            and b >= 0
            and not string_control(b, false)
            and (b != BACKSLASH or quote == SINGLE_QUOTE)
        ):
            end += 1
            b = byte_at(reader.data, end)

        if b == quote:
            let text = slice_text(reader, reader.pos, end)
            reader.pos = end + 1
            return ok(text)

    # Append through a builder: per-character concatenation is quadratic on long strings.
    var result = StringBuilder()
    var run = cursor(reader)

    while true:
        let c = advance(var reader)
        if c < 0:
            return error(invalid(reader, "unterminated string"))

        if c == quote:
            if not multiline:
                result.append(slice_text(reader, run, reader.pos - 1))
                return ok(result.build())

            if peek(reader) == quote and ahead(reader, 1) == quote:
                result.append(slice_text(reader, run, reader.pos - 1))
                advance(var reader)
                advance(var reader)

                var extra = 0

                while peek(reader) == quote and extra < 2:
                    advance(var reader)
                    result.append(quote_char(quote))
                    extra += 1

                return ok(result.build())

            continue

        if string_control(c, multiline):
            return error(invalid(reader, "control character in string"))
        if c != BACKSLASH or quote == SINGLE_QUOTE: continue

        result.append(slice_text(reader, run, reader.pos - 1))

        if (
            multiline
            and (
                peek(reader) == SPACE
                or peek(reader) == TAB
                or peek(reader) == NEWLINE
            )
        ):
            while peek(reader) == SPACE or peek(reader) == TAB: advance(var reader)
            if advance(var reader) != NEWLINE: return error(
                invalid(reader, "expected escaped newline")
            )

            while (
                peek(reader) == SPACE
                or peek(reader) == TAB
                or peek(reader) == NEWLINE
            ): advance(var reader)
            run = reader.pos
            continue

        let escaped = advance(var reader)

        if escaped == 98: result.append("\u{8}")
        else if escaped == 116: result.append("\t")
        else if escaped == 110: result.append("\n")
        else if escaped == 102: result.append("\u{c}")
        else if escaped == 114: result.append("\r")
        else if escaped == DOUBLE_QUOTE: result.append("\"")
        else if escaped == BACKSLASH: result.append("\\")
        else if escaped == 117 or escaped == 85:
            var count = 4
            if escaped == 85: count = 8

            let digits_start = cursor(reader)

            while count > 0:
                let digit = advance(var reader)
                if not hex_digit(digit):
                    return error(invalid(reader, "invalid Unicode escape"))

                count -= 1

            let parsed = parse_int(slice_text(reader, digits_start, reader.pos), 16)
            if parsed.is_error(): return error(
                invalid(reader, "invalid Unicode escape")
            )

            if let text = from_scalars([parsed.get()]):
                result.append(text)
            else:
                return error(invalid(reader, "invalid Unicode scalar"))
        else:
            return error(invalid(reader, "invalid string escape"))

        run = reader.pos

fn hex_digit(b: Int) Bool:
    return (b >= 48 and b <= 57) or (b >= 65 and b <= 70) or (b >= 97 and b <= 102)

fn bare_key_byte(b: Int) Bool:
    return (
        (b >= 97 and b <= 122)
        or (b >= 65 and b <= 90)
        or (b >= 48 and b <= 57)
        or b == 95
        or b == 45
    )

fn key_path(var reader: Reader) Result[List[String], TomlError]:
    var keys: List[String] = []

    while true:
        space(var reader, multiline: false)

        var key = ""

        if peek(reader) == DOUBLE_QUOTE or peek(reader) == SINGLE_QUOTE:
            key = try string_value(var reader, key: true)
        else:
            let start = cursor(reader)
            var end = start
            while bare_key_byte(byte_at(reader.data, end)): end += 1
            if end == start: return error(invalid(reader, "expected key"))

            key = slice_text(reader, start, end)
            reader.pos = end

        keys.append(key)
        space(var reader, multiline: false)
        if peek(reader) != DOT: return ok(keys)

        advance(var reader)

fn child(var reader: Reader, parent: Int, key: String, dotted: Bool) Result[
    Int, TomlError
]:
    if flags(reader, parent).sealed: return error(
        invalid(reader, "inline table is closed")
    )

    let existing = lookup(reader, parent, key)

    if existing.is_none():
        try allocate(var reader)

        let created = new_table(var reader, explicit: false, dotted)
        put(var reader, parent, key, Node.TableNode(created))
        return ok(created)

    let node = existing.get()

    match node:
        TableNode(value):
            let state = flags(reader, value)
            if state.sealed: return error(invalid(reader, "inline table is closed"))
            if dotted and state.explicit: return error(
                invalid(reader, "dotted key extends an explicit table")
            )

            return ok(value)
        TableArray(ids):
            if dotted: return error(invalid(reader, "dotted key extends a table array"))

            return ok(ids.last().get())
        _: return error(invalid(reader, "key is already a value"))

fn append_table(var reader: Reader, parent: Int, key: String, next: Int) Result[
    Unit, TomlError
]:
    let existing = lookup(reader, parent, key)

    if existing.is_none():
        try allocate(var reader)
        put_array(var reader, parent, key, [next])
        return ok(unit)

    let node = existing.get()

    match node:
        TableArray(ids):
            var grown = ids.clone()
            grown.append(next)
            put_array(var reader, parent, key, grown)
            return ok(unit)
        _: return error(invalid(reader, "table array conflicts with value"))

fn assign(var reader: Reader, parent: Int, keys: List[String], value: Node) Result[
    Unit, TomlError
]:
    var current = parent
    var index = 0

    while index < keys.length() - 1:
        current = try child(
            reader: var reader, parent: current, key: (keys.get(index).clone()),
            dotted: true
        )
        index += 1

    return assign_one(
        reader: var reader, parent: current, key: keys.last().get(), value: value
    )

# Adds a key that must not exist yet to an open table.
fn assign_one(var reader: Reader, parent: Int, key: String, value: Node) Result[
    Unit, TomlError
]:
    if flags(reader, parent).sealed: return error(
        invalid(reader, "duplicate or closed key")
    )

    let before = reader.entries.get(parent).length()
    reader.entries[parent].add_default(key.clone(), value)
    if reader.entries.get(parent).length() == before: return error(
        invalid(reader, "duplicate or closed key")
    )

    return ok(unit)

# Reads `key =` when the key is one plain bare word; otherwise leaves the cursor where it was.
fn simple_key(var reader: Reader) Optional[String]:
    space(var reader, multiline: false)

    let start = cursor(reader)
    var end = start
    while bare_key_byte(byte_at(reader.data, end)): end += 1
    if end == start: return none

    var after = end
    var b = byte_at(reader.data, after)

    while b == SPACE or b == TAB:
        after += 1
        b = byte_at(reader.data, after)

    if b != EQUALS: return none

    reader.pos = after + 1
    return slice_text(reader, start, end)

# Reads `keys = value` into the table, where `depth` is the nesting depth of the table.
fn key_value(var reader: Reader, table: Int, depth: Int) Result[Unit, TomlError]:
    if let key = simple_key(var reader):
        let value = try read_value(var reader, depth + 1)
        return assign_one(reader: var reader, parent: table, key: key, value: value)

    let keys = try key_path(var reader)
    if advance(var reader) != EQUALS: return error(invalid(reader, "expected equals"))

    let value = try read_value(var reader, depth + keys.length())
    return assign(reader: var reader, parent: table, keys: keys, value: value)

fn seal(var reader: Reader, value: Node) Unit:
    match value:
        TableNode(id):
            var state = flags(reader, id)
            if state.sealed: return unit

            state.sealed = true
            store_flags(var reader, id, state)
            for entry in reader.entries.get(id).clone(): seal(
                var reader, entry.value.clone()
            )
        ArrayNode(values):
            for item in values: seal(var reader, item)
        _: return unit

fn digits(text: String, alphabet: String) Bool:
    if text == "": return false

    var previous = false

    for c in text.split(""):
        if c == "_":
            if not previous: return false

            previous = false
        else:
            if not alphabet.contains(c): return false

            previous = true

    return previous

fn decimal_digits(text: String) Bool:
    return digits(text, "0123456789")

fn decimal_part(text: String) Bool:
    if not decimal_digits(text): return false

    let clean = text.replace("_", "")
    return clean == "0" or not clean.starts_with("0")

fn date_number(text: String, minimum: Int, maximum: Int) Bool:
    if not digits(text, "0123456789") or text.contains("_"): return false
    if let value = parse_int(text, 10):
        return value >= minimum and value <= maximum

    return false

fn date_valid(text: String) Bool:
    if (
        text.scalar_length() != 10
        or text.get(4, default: "") != "-"
        or text.get(7, default: "") != "-"
    ): return false

    let year = text.slice(0, 4).get("")
    let month = text.slice(5, 7).get("")
    let day = text.slice(8, 10).get("")
    if (not date_number(year, 0, 9999) or not date_number(month, 1, 12)): return false

    let m = month.parse_int().get()
    var maximum = 31
    if (m == 4 or m == 6 or m == 9 or m == 11): maximum = 30

    if m == 2:
        maximum = 28

        let y = year.parse_int().get()
        if y % 4 == 0 and (y % 100 != 0 or y % 400 == 0): maximum = 29

    return date_number(day, 1, maximum)

fn time_valid(text: String) Bool:
    if (
        text.scalar_length() < 8
        or text.get(2, default: "") != ":"
        or text.get(5, default: "") != ":"
    ): return false
    if not date_number(text.slice(0, 2).get(""), 0, 23): return false
    if not date_number(text.slice(3, 5).get(""), 0, 59): return false
    if not date_number(text.slice(6, 8).get(""), 0, 60): return false
    if text.scalar_length() == 8: return true

    let fraction = text.slice(9, text.scalar_length()).get("")
    return (
        text.get(8, default: "") == "."
        and decimal_digits(fraction)
        and not fraction.contains("_")
    )

fn datetime_valid(text: String) Bool:
    if date_valid(text): return true
    if time_valid(text): return true
    if (text.scalar_length() < 19 or not date_valid((text.slice(0, 10).get("")))): return false

    let separator = text.get(10, default: "")
    if (separator != "T" and separator != "t" and separator != " "): return false

    var rest = text.slice(11, text.scalar_length()).get("")

    if rest.ends_with("Z") or rest.ends_with("z"):
        rest = rest.slice(0, rest.scalar_length() - 1).get("")
    else if rest.contains("+") or rest.contains("-"):
        var index = rest.index_of("+").get(-1)
        if index < 0: index = rest.index_of("-").get(-1)

        let zone = rest.slice(index + 1, rest.scalar_length()).get("")
        if zone.scalar_length() != 5 or zone.get(2, default: "") != ":": return false
        if not date_number(zone.slice(0, 2).get(""), 0, 23): return false
        if not date_number(zone.slice(3, 5).get(""), 0, 59): return false

        rest = rest.slice(0, index).get("")

    return time_valid(rest)

fn scalar(reader: Reader, text: String, at: Int) Result[Node, TomlError]:
    if text == "true": return ok(Node.Leaf(TomlValue.BoolValue(true)))
    if text == "false": return ok(Node.Leaf(TomlValue.BoolValue(false)))
    if datetime_valid(text): return ok(Node.Leaf(TomlValue.DateTimeValue(text)))

    var clean = text.clone()
    var signed = false

    if clean.starts_with("+") or clean.starts_with("-"):
        signed = true
        clean = clean.slice(1, clean.scalar_length()).get("")

    var radix = 10
    var alphabet = "0123456789"

    if clean.starts_with("0x"):
        radix = 16
        alphabet = "0123456789abcdefABCDEF"
    else if clean.starts_with("0o"):
        radix = 8
        alphabet = "01234567"
    else if clean.starts_with("0b"):
        radix = 2
        alphabet = "01"

    if radix != 10:
        if (
            signed
            or not digits(
                clean.slice(2, clean.scalar_length()).get(""), alphabet
            )
        ):
            return error(invalid_at(reader, at, "invalid integer"))
        if let value = parse_int(
            (
                clean
                .slice(2, clean.scalar_length())
                .get("")
                .replace("_", "")
            ),
            radix
        ): return ok(Node.Leaf(TomlValue.IntValue(value)))

        return error(invalid_at(reader, at, "integer out of range"))

    # Bare words such as True, yes, or abc are not numbers, even when they
    # contain an e.
    if (
        clean != "inf"
        and clean != "nan"
        and not "0123456789".contains(clean.get(0, default: "x"))
    ): return error(invalid_at(reader, at, "invalid value"))

    if (
        clean == "inf"
        or clean == "nan"
        or clean.contains(".")
        or clean.contains("e")
        or clean.contains("E")
    ):
        if clean != "inf" and clean != "nan":
            let parts = clean.lower().split("e")
            if parts.length() > 2: return error(invalid_at(reader, at, "invalid float"))

            if parts.length() == 2:
                var exponent = parts.get(1).clone()
                if exponent.starts_with("+") or exponent.starts_with("-"): exponent = (
                    exponent
                    .slice(1, exponent.scalar_length())
                    .get("")
                )
                if not decimal_digits(exponent): return error(
                    invalid_at(reader, at, "invalid exponent")
                )

            let fraction = parts.first().get().split(".")
            if fraction.length() > 2 or not decimal_part(fraction.first().get()): return error(
                invalid_at(reader, at, "invalid float")
            )
            if fraction.length() == 2 and not decimal_digits(fraction.get(1)): return error(
                invalid_at(reader, at, "invalid fraction")
            )

        if clean == "inf":
            var infinity = -log(0.0)
            if text.starts_with("-"): infinity = -infinity
            return ok(Node.Leaf(TomlValue.FloatValue(infinity)))

        if clean == "nan": return ok(Node.Leaf(TomlValue.FloatValue(sqrt((-1.0)))))

        let number = text.replace("_", "")
        if let value = parse_float(number): return ok(
            Node.Leaf(TomlValue.FloatValue(value))
        )

        return error(invalid_at(reader, at, "float out of range"))

    if not decimal_part(clean): return error(invalid_at(reader, at, "invalid value"))
    if let value = parse_int(text.replace("_", ""), 10): return ok(
        Node.Leaf(TomlValue.IntValue(value))
    )

    return error(invalid_at(reader, at, "integer out of range"))

# Whether a byte ends a bare value token.
fn token_end(b: Int) Bool:
    return (
        b < 0
        or b == NEWLINE
        or b == TAB
        or b == HASH
        or b == COMMA
        or b == RIGHT_BRACKET
        or b == RIGHT_BRACE
        or b == SPACE
    )

# The byte offset after `count` scalars from the cursor.
fn scalar_offset(reader: Reader, count: Int) Int:
    var pos = cursor(reader)
    var left = count

    while left > 0 and pos < reader.data.length():
        pos += 1
        while (
            reader.data.get(pos, default: 0) >= 128
            and reader.data.get(pos, default: 0) < 192
        ): pos += 1
        left -= 1

    return pos

fn read_value(var reader: Reader, depth: Int) Result[Node, TomlError]:
    try allocate(var reader)
    try budget(reader, depth)
    space(var reader, multiline: false)

    let c = peek(reader)
    if c == DOUBLE_QUOTE or c == SINGLE_QUOTE: return ok(
        Node.Leaf(
            TomlValue.StringValue(try string_value(var reader, key: false))
        )
    )

    if c == LEFT_BRACKET:
        advance(var reader)

        var values: List[Node] = []
        space(var reader, multiline: true)

        while peek(reader) != RIGHT_BRACKET:
            values.append(try read_value(var reader, depth + 1))
            space(var reader, multiline: true)
            if peek(reader) == RIGHT_BRACKET: break
            if advance(var reader) != COMMA: return error(
                invalid(reader, "expected array comma")
            )

            space(var reader, multiline: true)

        advance(var reader)
        return ok(Node.ArrayNode(values))

    if c == LEFT_BRACE:
        advance(var reader)

        let result = new_table(var reader, explicit: true, dotted: false)
        space(var reader, multiline: false)

        if peek(reader) != RIGHT_BRACE:
            while true:
                try key_value(var reader, result, depth)
                space(var reader, multiline: false)
                if peek(reader) == RIGHT_BRACE: break
                if advance(var reader) != COMMA: return error(
                    invalid(reader, "expected inline table comma")
                )

        advance(var reader)

        let node = Node.TableNode(result)
        seal(var reader, node.clone())
        return ok(node)

    let start = cursor(reader)
    var end = start
    while not token_end(byte_at(reader.data, end)): end += 1

    # Short plain decimal integers, the common scalar, skip the general classifier.
    var sign = 0
    if c == 45 or c == 43: sign = 1

    let width = end - start - sign

    if (
        width >= 1
        and width <= 18
        and (reader.data.get(start + sign).to_int() != 48 or width == 1)
    ):
        var number = 0
        var index = start + sign

        while index < end:
            let digit = reader.data.get(index).to_int() - 48

            if digit < 0 or digit > 9:
                number = -1
                break

            number = number * 10 + digit
            index += 1

        if number >= 0:
            reader.pos = end
            if c == 45: number = -number
            return ok(Node.Leaf(TomlValue.IntValue(number)))

    var text = slice_text(reader, start, end)
    reader.pos = end

    # A space may separate date and time, but otherwise ends the token.
    if (
        date_valid(text)
        and peek(reader) == SPACE
        and byte_at(reader.data, scalar_offset(reader, 3)) == 58
    ):
        end += 1
        while not token_end(byte_at(reader.data, end)): end += 1
        text = slice_text(reader, start, end)
        reader.pos = end

    # Report token errors where the token starts, not where it ended.
    return scalar(reader, text, start)

# Counts the values of the finished document against the limits.
type Budget:
    limits: TomlLimits
    values: Int

fn materialize(
    tables: List[Map[String, Node]],
    node: Node,
    depth: Int,
    var budget: Budget
) Result[TomlValue, TomlError]:
    if not within(depth, budget.limits.max_depth): return error(TomlError.LimitExceeded)

    budget.values += 1
    if not within(budget.values, budget.limits.max_values): return error(
        TomlError.LimitExceeded
    )

    match node:
        Leaf(value): return ok(value.clone())
        TableNode(id):
            var entries = Map[String, TomlValue]()
            for entry in tables.get(id):
                entries.add(
                    entry.key.clone(),
                    try materialize(
                        tables, entry.value, (depth + 1), var budget
                    )
                )
            return ok(TomlValue.TableValue(entries))
        ArrayNode(values):
            var result: List[TomlValue] = []
            for value in values: result.append(
                try materialize(tables, value, (depth + 1), var budget)
            )
            return ok(TomlValue.ArrayValue(result))
        TableArray(ids):
            var result: List[TomlValue] = []
            for id in ids: result.append(
                try materialize(
                    tables, Node.TableNode(id), (depth + 1), var budget
                )
            )
            return ok(TomlValue.ArrayValue(result))

# ASCII control characters other than tab and newline, which no TOML document may contain.
fn control_pattern() Regex:
    return compile("[\\x00-\\x08\\x0b-\\x1f\\x7f]").get()

# Parses a TOML document into a table value and reports source line and column on invalid input.
export fn parse(
    text: String,
    limits: Optional[TomlLimits] = none
) Result[TomlValue, TomlError]:
    var options = default_limits()
    if let value = limits:
        options = value
    for limit in [options.max_bytes, options.max_depth, options.max_values]:
        if let value = limit:
            if value < 0: return error(TomlError.InvalidInput)
    if not within(text.byte_length(), options.max_bytes): return error(
        TomlError.LimitExceeded
    )

    # TOML permits CR only as part of CRLF. Report the first offending scalar
    # at its own line and column.
    var normalized = text.clone()
    if text.contains("\r"): normalized = text.replace("\r\n", "\n")

    var reader = Reader(
        data: normalized.to_bytes(), pos: 0, limits: options, values: 0, tables: [],
        entries: []
    )

    if let span = control_pattern().find_span(normalized):
        let place = locate(reader.data, span.get(0))
        var reason = "invalid control character"
        if reader.data.get(span.get(0)) == 13: reason = "bare carriage return"
        return error(
            TomlError.InvalidData(
                line: place.get(0), column: place.get(1), reason: reason
            )
        )

    try allocate(var reader)

    let root = new_table(var reader, explicit: true, dotted: false)
    var current = root
    var current_depth = 1

    while true:
        space(var reader, multiline: true)
        if peek(reader) < 0: break

        if peek(reader) == LEFT_BRACKET:
            advance(var reader)

            var array = false

            if peek(reader) == LEFT_BRACKET:
                advance(var reader)
                array = true

            let keys = try key_path(var reader)
            if (
                advance(var reader) != RIGHT_BRACKET
                or (array and advance(var reader) != RIGHT_BRACKET)
            ): return error(invalid(reader, "expected closing table bracket"))

            var parent = root
            var index = 0

            while index < keys.length() - 1:
                parent = try child(
                    reader: var reader, parent: parent, key: (keys.get(index).clone()),
                    dotted: false
                )
                index += 1

            let key = keys.last().get()
            if flags(reader, parent).sealed: return error(
                invalid(reader, "inline table is closed")
            )

            if array:
                try allocate(var reader)

                let next = new_table(var reader, explicit: true, dotted: false)
                try append_table(
                    reader: var reader, parent: parent, key: key, next: next
                )
                current = next
            else:
                current = try child(
                    reader: var reader, parent: parent, key: key, dotted: false
                )

                var state = flags(reader, current)
                if state.explicit or state.dotted: return error(
                    invalid(reader, "table already defined")
                )

                state.explicit = true
                store_flags(var reader, current, state)

            current_depth = keys.length() + 1
            if array: current_depth += 1
            try budget(reader, current_depth)
        else:
            try key_value(var reader, current, current_depth)

        space(var reader, multiline: false)
        if peek(reader) == HASH:
            while peek(reader) >= 0 and peek(reader) != NEWLINE: advance(var reader)
        if peek(reader) >= 0 and advance(var reader) != NEWLINE: return error(
            invalid(reader, "unexpected trailing text")
        )

    var budget = Budget(limits: reader.limits.clone(), values: 0)
    return materialize(reader.entries, Node.TableNode(root), 1, var budget)

type Writer:
    out: StringBuilder
    started: Bool

fn hex4(code: Int) String:
    var digits = code.to_string_radix(16)
    while digits.length() < 4: digits = "0".concat(digits)
    return digits

fn quote_text(text: String) String:
    var result = StringBuilder()
    result.append("\"")

    for c in text.chars():
        let code = c.scalar_at(0)

        if c == "\"": result.append("\\\"")
        else if c == "\\": result.append("\\\\")
        else if c == "\n": result.append("\\n")
        else if c == "\t": result.append("\\t")
        else if c == "\r": result.append("\\r")
        else if code == 8: result.append("\\b")
        else if code == 12: result.append("\\f")
        else if code < 32 or code == 127:
            result.append("\\u")
            result.append(hex4(code))
        else: result.append(c)

    result.append("\"")
    return result.build()

fn format_key(key: String) String:
    var bare = key != ""
    for c in key.chars():
        if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(
            c
        ): bare = false
    if bare: return key

    return quote_text(key)

fn format_float(value: Float) String:
    if value.is_nan(): return "nan"

    if not value.is_finite():
        if value < 0.0: return "-inf"

        return "inf"

    let text = value.to_string()
    if (text.contains(".") or text.contains("e") or text.contains("E")): return text

    return text.concat(".0")

fn inline_value(value: TomlValue) String:
    match value:
        StringValue(text): return quote_text(text)
        IntValue(number): return number.to_string()
        FloatValue(number): return format_float(number)
        BoolValue(flag): return flag.to_string()
        DateTimeValue(text): return text
        ArrayValue(values):
            var parts: List[String] = []
            for item in values: parts.append(inline_value(item))
            return "[".concat(parts.join(", ")).concat("]")
        TableValue(values):
            var parts: List[String] = []
            for entry in values.entries(): parts.append(
                format_key(entry.key.clone()).concat(" = ").concat(
                    inline_value(entry.value.clone())
                )
            )
            if parts.is_empty(): return "\{\}"

            return "\{ ".concat(parts.join(", ")).concat(" \}")

fn table_items(values: List[TomlValue]) List[Map[String, TomlValue]]:
    var tables: List[Map[String, TomlValue]] = []

    for item in values:
        match item:
            TableValue(table): tables.append(table.clone())
            _: return []

    return tables

fn dotted(path: List[String]) String:
    var parts: List[String] = []
    for key in path: parts.append(format_key(key))
    return parts.join(".")

fn emit_header(var writer: Writer, header: String) Unit:
    if writer.started: writer.out.append("\n")
    writer.out.append(header)
    writer.out.append("\n")
    writer.started = true

fn section_kind(value: TomlValue) Int:
    match value:
        TableValue(_): return 1
        ArrayValue(elements):
            if (
                not elements.is_empty()
                and table_items(
                    elements.clone()
                ).length() == elements.length()
            ): return 2

            return 0
        _: return 0

fn emit_one(
    var writer: Writer, path: List[String], brackets: String,
    table: Map[String, TomlValue]
) Unit:
    if brackets == "[[": emit_header(
        var writer, "[[".concat(dotted(path.clone())).concat("]]")
    )
    else: emit_header(var writer, "[".concat(dotted(path.clone())).concat("]"))

    emit_table(var writer, path, table)

fn emit_table(var writer: Writer, path: List[String], values: Map[String, TomlValue]) Unit:
    for entry in values.entries():
        if section_kind(entry.value.clone()) == 0: writer.out.append(
            (
                format_key(entry.key.clone())
                .concat(" = ")
                .concat(inline_value(entry.value.clone()))
                .concat("\n")
            )
        )

    for entry in values.entries():
        var child = path.clone()
        child.append(entry.key.clone())

        match entry.value:
            TableValue(table): emit_one(
                writer: var writer, path: child, brackets: "[", table: table
            )
            ArrayValue(elements):
                if section_kind(entry.value.clone()) == 2:
                    for table in table_items(elements.clone()): emit_one(
                        writer: var writer, path: child.clone(), brackets: "[[",
                        table: table
                    )
            _: unit

fn datetimes_valid(value: TomlValue) Bool:
    match value:
        DateTimeValue(text): return datetime_valid(text)
        ArrayValue(values):
            for item in values:
                if not datetimes_valid(item): return false
            return true
        TableValue(values):
            for entry in values.entries():
                if not datetimes_valid(entry.value.clone()): return false
            return true
        _: return true

# Serializes a table value as a TOML document. Tables and arrays of tables use headers; other values are written inline.
export fn stringify(
    value: TomlValue,
    max_bytes: Optional[Int] = none
) Result[String, TomlError]:
    if let limit = max_bytes:
        if limit < 0: return error(TomlError.InvalidInput)

    let root = match value:
        TableValue(values): values.clone()
        _: return error(TomlError.InvalidInput)

    if not datetimes_valid(value): return error(TomlError.InvalidInput)

    var writer = Writer(StringBuilder(), started: false)
    emit_table(var writer, [], root)

    let text = writer.out.build()
    if not within(text.byte_length(), max_bytes): return error(TomlError.LimitExceeded)

    return ok(text)
