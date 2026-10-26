# TOML 1.0 parser implemented in Manuscript.
from "@std/math.ms" import parse_int, parse_float
from "@std/string.ms" import from_scalars, StringBuilder
from "@std/math.ms" import log, sqrt

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
    def message() -> String:
        match self:
            case InvalidInput: return "invalid TOML input"
            case InvalidData(line, column, reason): return f"TOML {line}:{column}: {reason}"
            case LimitExceeded: return "TOML limit exceeded"

type Reader:
    chars: List[String]
    pos: Int
    line: Int
    column: Int
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

def new_table(var reader: Reader, explicit: Bool, dotted: Bool) -> Int:
    reader.tables.append(Table(explicit: explicit, dotted: dotted, sealed: False))
    reader.entries.append(Map[String, Node]())
    return reader.tables.length() - 1

def flags(reader: Reader, id: Int) -> Table:
    return reader.tables.get(id)

def store_flags(var reader: Reader, id: Int, flags: Table) -> Unit:
    reader.tables.set(id, flags)

def lookup(reader: Reader, id: Int, key: String) -> Optional[Node]:
    return reader.entries.get(id).get(key)

def contains_key(reader: Reader, id: Int, key: String) -> Bool:
    return reader.entries.get(id).contains(key)

# Adds an entry to the table's map in place.
def put(var reader: Reader, id: Int, key: String, node: Node) -> Unit:
    reader.entries[id].add(key, node)

def put_array(var reader: Reader, id: Int, key: String, ids: List[Int]) -> Unit:
    put(var reader, id, key, Node.TableArray(ids))

def peek(reader: Reader) -> String:
    return reader.chars.get(reader.pos, default: "").clone()

def ahead(reader: Reader, offset: Int) -> String:
    return reader.chars.get(reader.pos + offset, default: "").clone()

def advance(var reader: Reader) -> String:
    let c = peek(reader)
    if c == "": return c.clone()

    reader.pos += 1

    if c == "\n":
        reader.line += 1
        reader.column = 1
    else:
        reader.column += 1

    return c.clone()

def invalid(reader: Reader, reason: String) -> TomlError:
    return TomlError.InvalidData(
        line: reader.line, column: reader.column, reason: reason
    )

def space(var reader: Reader, multiline: Bool) -> Unit:
    while True:
        let c = peek(reader)

        if (c == " " or c == "\t" or (multiline and c == "\n")):
            advance(var reader)
        elif multiline and c == "#":
            while peek(reader) != "" and peek(reader) != "\n": advance(var reader)
        else:
            break

# Limits applied when `parse` is called without any: deep nesting and alias expansion are
# the usual resource attacks. Pass a `TomlLimits` (even an empty one) to lift or change them.
def default_limits() -> TomlLimits:
    return TomlLimits(max_depth: some(10000), max_values: some(1000000))

def within(value: Int, limit: Optional[Int]) -> Bool:
    if let maximum = limit:
        return value <= maximum

    return True

def allocate(var reader: Reader) -> Result[Unit, TomlError]:
    reader.values += 1
    if not within(reader.values, reader.limits.max_values): return error(
        TomlError.LimitExceeded
    )

    return ok(())

def budget(reader: Reader, depth: Int) -> Result[Unit, TomlError]:
    if not within(depth, reader.limits.max_depth): return error(TomlError.LimitExceeded)

    return ok(())

# Basic and literal strings, including multiline delimiters and escaped newline folding.
def string_value(var reader: Reader, key: Bool) -> Result[String, TomlError]:
    let quote = advance(var reader)
    var multiline = False

    if (not key and peek(reader) == quote and ahead(reader, 1) == quote):
        advance(var reader)
        advance(var reader)
        multiline = True
        if peek(reader) == "\n": advance(var reader)

    # Append through a builder: per-character concatenation is quadratic on long strings.
    var result = StringBuilder()

    while True:
        let c = advance(var reader)
        if c == "": return error(invalid(reader, "unterminated string"))

        if c == quote:
            if not multiline: return ok(result.build())

            if peek(reader) == quote and ahead(reader, 1) == quote:
                advance(var reader)
                advance(var reader)

                var extra = 0

                while peek(reader) == quote and extra < 2:
                    result.append(advance(var reader))
                    extra += 1

                return ok(result.build())

            result.append(c)
            continue

        let code = c.scalar_at(0)
        if (code < 32 and c != "\t" and not (multiline and c == "\n")) or code == 127:
            return error(invalid(reader, "control character in string"))

        if c != "\\" or quote == "'":
            result.append(c)
            continue

        if (
            multiline
            and (
                peek(reader) == " "
                or peek(reader) == "\t"
                or peek(reader) == "\n"
            )
        ):
            while peek(reader) == " " or peek(reader) == "\t": advance(var reader)
            if advance(var reader) != "\n": return error(
                invalid(reader, "expected escaped newline")
            )

            while (peek(reader) == " " or peek(reader) == "\t" or peek(reader) == "\n"): advance(
                var reader
            )
            continue

        let escaped = advance(var reader)

        if escaped == "b": result.append(f"\u{8}")
        elif escaped == "t": result.append("\t")
        elif escaped == "n": result.append("\n")
        elif escaped == "f": result.append(f"\u{c}")
        elif escaped == "r": result.append("\r")
        elif escaped == "\"" or escaped == "\\": result.append(escaped)
        elif escaped == "u" or escaped == "U":
            var count = 4
            if escaped == "U": count = 8

            var hex = ""

            while count > 0:
                let digit = advance(var reader)
                if digit == "" or not "0123456789abcdefABCDEF".contains(digit):
                    return error(invalid(reader, "invalid Unicode escape"))

                hex = hex.concat(digit)
                count -= 1

            let parsed = parse_int(hex, 16)
            if parsed.is_error(): return error(
                invalid(reader, "invalid Unicode escape")
            )

            if let text = from_scalars([parsed.get()]):
                result.append(text)
            else:
                return error(invalid(reader, "invalid Unicode scalar"))
        else:
            return error(invalid(reader, "invalid string escape"))

def key_path(var reader: Reader) -> Result[List[String], TomlError]:
    var keys: List[String] = []

    while True:
        space(var reader, multiline: False)

        var key = ""

        if peek(reader) == "\"" or peek(reader) == "'":
            key = try string_value(var reader, key: True)
        else:
            while (
                peek(reader) != ""
                and "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(
                    peek(reader)
                )
            ):
                key = key.concat(advance(var reader))
            if key == "": return error(invalid(reader, "expected key"))

        keys.append(key)
        space(var reader, multiline: False)
        if peek(reader) != ".": return ok(keys)

        advance(var reader)

def child(var reader: Reader, parent: Int, key: String, dotted: Bool) -> Result[
    Int, TomlError
]:
    if flags(reader, parent).sealed: return error(
        invalid(reader, "inline table is closed")
    )

    let existing = lookup(reader, parent, key)

    if existing.is_none():
        try allocate(var reader)

        let created = new_table(var reader, explicit: False, dotted)
        put(var reader, parent, key, Node.TableNode(created))
        return ok(created)

    let node = existing.get()

    match node:
        case TableNode(value):
            let state = flags(reader, value)
            if state.sealed: return error(invalid(reader, "inline table is closed"))
            if dotted and state.explicit: return error(
                invalid(reader, "dotted key extends an explicit table")
            )

            return ok(value)
        case TableArray(ids):
            if dotted: return error(invalid(reader, "dotted key extends a table array"))

            return ok(ids.last().get())
        case _: return error(invalid(reader, "key is already a value"))

def append_table(var reader: Reader, parent: Int, key: String, next: Int) -> Result[
    Unit, TomlError
]:
    let existing = lookup(reader, parent, key)

    if existing.is_none():
        try allocate(var reader)
        put_array(var reader, parent, key, [next])
        return ok(())

    let node = existing.get()

    match node:
        case TableArray(ids):
            var grown = ids.clone()
            grown.append(next)
            put_array(var reader, parent, key, grown)
            return ok(())
        case _: return error(invalid(reader, "table array conflicts with value"))

def assign(var reader: Reader, parent: Int, keys: List[String], value: Node) -> Result[
    Unit, TomlError
]:
    var current = parent
    var index = 0

    while index < keys.length() - 1:
        current = try child(
            reader: var reader, parent: current, key: (keys.get(index).clone()),
            dotted: True
        )
        index += 1

    let key = keys.last().get()
    if flags(reader, current).sealed or contains_key(reader, current, key): return error(
        invalid(reader, "duplicate or closed key")
    )

    put(var reader, current, key, value)
    return ok(())

def seal(var reader: Reader, value: Node) -> Unit:
    match value:
        case TableNode(id):
            var state = flags(reader, id)
            if state.sealed: return ()

            state.sealed = True
            store_flags(var reader, id, state)
            for entry in reader.entries.get(id).clone(): seal(
                var reader, entry.value.clone()
            )
        case ArrayNode(values):
            for item in values: seal(var reader, item)
        case _: return ()

def digits(text: String, alphabet: String) -> Bool:
    if text == "": return False

    var previous = False

    for c in text.split(""):
        if c == "_":
            if not previous: return False

            previous = False
        else:
            if not alphabet.contains(c): return False

            previous = True

    return previous

def decimal_digits(text: String) -> Bool:
    return digits(text, "0123456789")

def decimal_part(text: String) -> Bool:
    if not decimal_digits(text): return False

    let clean = text.replace("_", "")
    return clean == "0" or not clean.starts_with("0")

def date_number(text: String, minimum: Int, maximum: Int) -> Bool:
    if not digits(text, "0123456789") or text.contains("_"): return False
    if let value = parse_int(text, 10):
        return value >= minimum and value <= maximum

    return False

def date_valid(text: String) -> Bool:
    if (
        text.scalar_length() != 10
        or text.get(4, default: "") != "-"
        or text.get(7, default: "") != "-"
    ): return False

    let year = text.slice(0, 4).get("")
    let month = text.slice(5, 7).get("")
    let day = text.slice(8, 10).get("")
    if (not date_number(year, 0, 9999) or not date_number(month, 1, 12)): return False

    let m = month.parse_int().get()
    var maximum = 31
    if (m == 4 or m == 6 or m == 9 or m == 11): maximum = 30

    if m == 2:
        maximum = 28

        let y = year.parse_int().get()
        if y % 4 == 0 and (y % 100 != 0 or y % 400 == 0): maximum = 29

    return date_number(day, 1, maximum)

def time_valid(text: String) -> Bool:
    if (
        text.scalar_length() < 8
        or text.get(2, default: "") != ":"
        or text.get(5, default: "") != ":"
    ): return False
    if not date_number(text.slice(0, 2).get(""), 0, 23): return False
    if not date_number(text.slice(3, 5).get(""), 0, 59): return False
    if not date_number(text.slice(6, 8).get(""), 0, 60): return False
    if text.scalar_length() == 8: return True

    let fraction = text.slice(9, text.scalar_length()).get("")
    return (
        text.get(8, default: "") == "."
        and decimal_digits(fraction)
        and not fraction.contains("_")
    )

def datetime_valid(text: String) -> Bool:
    if date_valid(text): return True
    if time_valid(text): return True
    if (text.scalar_length() < 19 or not date_valid((text.slice(0, 10).get("")))): return False

    let separator = text.get(10, default: "")
    if (separator != "T" and separator != "t" and separator != " "): return False

    var rest = text.slice(11, text.scalar_length()).get("")

    if rest.ends_with("Z") or rest.ends_with("z"):
        rest = rest.slice(0, rest.scalar_length() - 1).get("")
    elif rest.contains("+") or rest.contains("-"):
        var index = rest.index_of("+").get(-1)
        if index < 0: index = rest.index_of("-").get(-1)

        let zone = rest.slice(index + 1, rest.scalar_length()).get("")
        if zone.scalar_length() != 5 or zone.get(2, default: "") != ":": return False
        if not date_number(zone.slice(0, 2).get(""), 0, 23): return False
        if not date_number(zone.slice(3, 5).get(""), 0, 59): return False

        rest = rest.slice(0, index).get("")

    return time_valid(rest)

def scalar(reader: Reader, text: String) -> Result[Node, TomlError]:
    if text == "true": return ok(Node.Leaf(TomlValue.BoolValue(True)))
    if text == "false": return ok(Node.Leaf(TomlValue.BoolValue(False)))
    if datetime_valid(text): return ok(Node.Leaf(TomlValue.DateTimeValue(text)))

    var clean = text.clone()
    var signed = False

    if clean.starts_with("+") or clean.starts_with("-"):
        signed = True
        clean = clean.slice(1, clean.scalar_length()).get("")

    var radix = 10
    var alphabet = "0123456789"

    if clean.starts_with("0x"):
        radix = 16
        alphabet = "0123456789abcdefABCDEF"
    elif clean.starts_with("0o"):
        radix = 8
        alphabet = "01234567"
    elif clean.starts_with("0b"):
        radix = 2
        alphabet = "01"

    if radix != 10:
        if (
            signed
            or not digits(
                clean.slice(2, clean.scalar_length()).get(""), alphabet
            )
        ):
            return error(invalid(reader, "invalid integer"))
        if let value = parse_int(
            (
                clean
                .slice(2, clean.scalar_length())
                .get("")
                .replace("_", "")
            ),
            radix
        ): return ok(Node.Leaf(TomlValue.IntValue(value)))

        return error(invalid(reader, "integer out of range"))

    # Bare words such as True, yes, or abc are not numbers, even when they
    # contain an e.
    if (
        clean != "inf"
        and clean != "nan"
        and not "0123456789".contains(clean.get(0, default: "x"))
    ): return error(invalid(reader, "invalid value"))

    if (
        clean == "inf"
        or clean == "nan"
        or clean.contains(".")
        or clean.contains("e")
        or clean.contains("E")
    ):
        if clean != "inf" and clean != "nan":
            let parts = clean.lower().split("e")
            if parts.length() > 2: return error(invalid(reader, "invalid float"))

            if parts.length() == 2:
                var exponent = parts.get(1).clone()
                if exponent.starts_with("+") or exponent.starts_with("-"): exponent = (
                    exponent
                    .slice(1, exponent.scalar_length())
                    .get("")
                )
                if not decimal_digits(exponent): return error(
                    invalid(reader, "invalid exponent")
                )

            let fraction = parts.first().get().split(".")
            if fraction.length() > 2 or not decimal_part(fraction.first().get()): return error(
                invalid(reader, "invalid float")
            )
            if fraction.length() == 2 and not decimal_digits(fraction.get(1)): return error(
                invalid(reader, "invalid fraction")
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

        return error(invalid(reader, "float out of range"))

    if not decimal_part(clean): return error(invalid(reader, "invalid value"))
    if let value = parse_int(text.replace("_", ""), 10): return ok(
        Node.Leaf(TomlValue.IntValue(value))
    )

    return error(invalid(reader, "integer out of range"))

def read_value(var reader: Reader, depth: Int) -> Result[Node, TomlError]:
    try allocate(var reader)
    try budget(reader, depth)
    space(var reader, multiline: False)

    let c = peek(reader)
    if c == "\"" or c == "'": return ok(
        Node.Leaf(
            TomlValue.StringValue(try string_value(var reader, key: False))
        )
    )

    if c == "[":
        advance(var reader)

        var values: List[Node] = []
        space(var reader, multiline: True)

        while peek(reader) != "]":
            values.append(try read_value(var reader, depth + 1))
            space(var reader, multiline: True)
            if peek(reader) == "]": break
            if advance(var reader) != ",": return error(
                invalid(reader, "expected array comma")
            )

            space(var reader, multiline: True)

        advance(var reader)
        return ok(Node.ArrayNode(values))

    if c == "{":
        advance(var reader)

        let result = new_table(var reader, explicit: True, dotted: False)
        space(var reader, multiline: False)

        if peek(reader) != "}":
            while True:
                let keys = try key_path(var reader)
                if advance(var reader) != "=": return error(
                    invalid(reader, "expected equals")
                )

                let value = try read_value(var reader, depth + keys.length())
                try assign(reader: var reader, parent: result, keys: keys, value: value)
                space(var reader, multiline: False)
                if peek(reader) == "}": break
                if advance(var reader) != ",": return error(
                    invalid(reader, "expected inline table comma")
                )

        advance(var reader)

        let node = Node.TableNode(result)
        seal(var reader, node.clone())
        return ok(node)

    var text = ""
    let start_line = reader.line
    let start_column = reader.column
    while (
        peek(reader) != ""
        and peek(reader) != "\n"
        and peek(reader) != "\t"
        and peek(reader) != "#"
        and peek(reader) != ","
        and peek(reader) != "]"
        and peek(reader) != "}"
        and peek(reader) != " "
    ):
        text = text.concat(advance(var reader))

    # A space may separate date and time, but otherwise ends the token.
    if (date_valid(text) and peek(reader) == " " and ahead(reader, 3) == ":"):
        text = text.concat(advance(var reader))
        while (
            peek(reader) != ""
            and peek(reader) != "\n"
            and peek(reader) != " "
            and peek(reader) != "\t"
            and peek(reader) != "#"
            and peek(reader) != ","
            and peek(reader) != "]"
            and peek(reader) != "}"
        ):
            text = text.concat(advance(var reader))

    # Report token errors where the token starts, not where it ended.
    let end_line = reader.line
    let end_column = reader.column
    reader.line = start_line
    reader.column = start_column

    let result = scalar(reader, text)
    reader.line = end_line
    reader.column = end_column
    return result

def materialize(var reader: Reader, node: Node, depth: Int) -> Result[
    TomlValue, TomlError
]:
    try budget(reader, depth)
    reader.values += 1
    if not within(reader.values, reader.limits.max_values): return error(
        TomlError.LimitExceeded
    )

    match node:
        case Leaf(value): return ok(value)
        case TableNode(id):
            var entries = Map[String, TomlValue]()
            for entry in reader.entries.get(id).clone():
                entries.add(
                    entry.key.clone(),
                    try materialize(
                        var reader, entry.value.clone(), (depth + 1)
                    )
                )
            return ok(TomlValue.TableValue(entries))
        case ArrayNode(values):
            var result: List[TomlValue] = []
            for value in values: result.append(
                try materialize(var reader, value, (depth + 1))
            )
            return ok(TomlValue.ArrayValue(result))
        case TableArray(ids):
            var result: List[TomlValue] = []
            for id in ids: result.append(
                try materialize(
                    var reader, Node.TableNode(id), (depth + 1)
                )
            )
            return ok(TomlValue.ArrayValue(result))

# Parses a TOML document into a table value and reports source line and column on invalid input.
export def parse(
    text: String,
    limits: Optional[TomlLimits] = none
) -> Result[TomlValue, TomlError]:
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
    let normalized = text.replace("\r\n", "\n")
    var scan_line = 1
    var scan_column = 1

    for code in normalized.scalar_values():
        if code == 13: return error(
            TomlError.InvalidData(
                line: scan_line, column: scan_column, reason: "bare carriage return"
            )
        )
        if (code < 32 and code != 9 and code != 10) or code == 127: return error(
            TomlError.InvalidData(
                line: scan_line, column: scan_column,
                reason: "invalid control character"
            )
        )

        if code == 10:
            scan_line += 1
            scan_column = 1
        else: scan_column += 1

    var reader = Reader(
        chars: normalized.split(""), pos: 0, line: 1, column: 1, limits: options,
        values: 0, tables: [], entries: []
    )
    try allocate(var reader)

    let root = new_table(var reader, explicit: True, dotted: False)
    var current = root
    var current_depth = 1

    while True:
        space(var reader, multiline: True)
        if peek(reader) == "": break

        if peek(reader) == "[":
            advance(var reader)

            var array = False

            if peek(reader) == "[":
                advance(var reader)
                array = True

            let keys = try key_path(var reader)
            if advance(var reader) != "]" or (array and advance(var reader) != "]"): return error(
                invalid(reader, "expected closing table bracket")
            )

            var parent = root
            var index = 0

            while index < keys.length() - 1:
                parent = try child(
                    reader: var reader, parent: parent, key: (keys.get(index).clone()),
                    dotted: False
                )
                index += 1

            let key = keys.last().get()
            if flags(reader, parent).sealed: return error(
                invalid(reader, "inline table is closed")
            )

            if array:
                try allocate(var reader)

                let next = new_table(var reader, explicit: True, dotted: False)
                try append_table(
                    reader: var reader, parent: parent, key: key, next: next
                )
                current = next
            else:
                current = try child(
                    reader: var reader, parent: parent, key: key, dotted: False
                )

                var state = flags(reader, current)
                if state.explicit or state.dotted: return error(
                    invalid(reader, "table already defined")
                )

                state.explicit = True
                store_flags(var reader, current, state)

            current_depth = keys.length() + 1
            if array: current_depth += 1
            try budget(reader, current_depth)
        else:
            let keys = try key_path(var reader)
            if advance(var reader) != "=": return error(
                invalid(reader, "expected equals")
            )

            let value = try read_value(var reader, (current_depth + keys.length()))
            try assign(reader: var reader, parent: current, keys: keys, value: value)

        space(var reader, multiline: False)
        if peek(reader) == "#":
            while peek(reader) != "" and peek(reader) != "\n": advance(var reader)
        if peek(reader) != "" and advance(var reader) != "\n": return error(
            invalid(reader, "unexpected trailing text")
        )

    reader.values = 0
    return materialize(var reader, Node.TableNode(root), 1)

type Writer:
    out: StringBuilder
    started: Bool

def hex4(code: Int) -> String:
    var digits = code.to_string_radix(16)
    while digits.length() < 4: digits = "0".concat(digits)
    return digits

def quote_text(text: String) -> String:
    var result = StringBuilder()
    result.append("\"")

    for c in text.chars():
        let code = c.scalar_at(0)

        if c == "\"": result.append("\\\"")
        elif c == "\\": result.append("\\\\")
        elif c == "\n": result.append("\\n")
        elif c == "\t": result.append("\\t")
        elif c == "\r": result.append("\\r")
        elif code == 8: result.append("\\b")
        elif code == 12: result.append("\\f")
        elif code < 32 or code == 127:
            result.append("\\u")
            result.append(hex4(code))
        else: result.append(c)

    result.append("\"")
    return result.build()

def format_key(key: String) -> String:
    var bare = key != ""
    for c in key.chars():
        if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(
            c
        ): bare = False
    if bare: return key

    return quote_text(key)

def format_float(value: Float) -> String:
    if value.is_nan(): return "nan"

    if not value.is_finite():
        if value < 0.0: return "-inf"

        return "inf"

    let text = value.to_string()
    if (text.contains(".") or text.contains("e") or text.contains("E")): return text

    return text.concat(".0")

def inline_value(value: TomlValue) -> String:
    match value:
        case StringValue(text): return quote_text(text)
        case IntValue(number): return number.to_string()
        case FloatValue(number): return format_float(number)
        case BoolValue(flag): return flag.to_string()
        case DateTimeValue(text): return text
        case ArrayValue(values):
            var parts: List[String] = []
            for item in values: parts.append(inline_value(item))
            return "[".concat(parts.join(", ")).concat("]")
        case TableValue(values):
            var parts: List[String] = []
            for entry in values.entries(): parts.append(
                format_key(entry.key.clone()).concat(" = ").concat(
                    inline_value(entry.value.clone())
                )
            )
            if parts.is_empty(): return "{}"

            return "{ ".concat(parts.join(", ")).concat(" }")

def table_items(values: List[TomlValue]) -> List[Map[String, TomlValue]]:
    var tables: List[Map[String, TomlValue]] = []

    for item in values:
        match item:
            case TableValue(table): tables.append(table.clone())
            case _: return []

    return tables

def dotted(path: List[String]) -> String:
    var parts: List[String] = []
    for key in path: parts.append(format_key(key))
    return parts.join(".")

def emit_header(var writer: Writer, header: String) -> Unit:
    if writer.started: writer.out.append("\n")
    writer.out.append(header)
    writer.out.append("\n")
    writer.started = True

def section_kind(value: TomlValue) -> Int:
    match value:
        case TableValue(_): return 1
        case ArrayValue(elements):
            if (
                not elements.is_empty()
                and table_items(
                    elements.clone()
                ).length() == elements.length()
            ): return 2

            return 0
        case _: return 0

def emit_one(
    var writer: Writer, path: List[String], brackets: String,
    table: Map[String, TomlValue]
) -> Unit:
    if brackets == "[[": emit_header(
        var writer, "[[".concat(dotted(path.clone())).concat("]]")
    )
    else: emit_header(var writer, "[".concat(dotted(path.clone())).concat("]"))

    emit_table(var writer, path, table)

def emit_table(var writer: Writer, path: List[String], values: Map[String, TomlValue]) -> Unit:
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
            case TableValue(table): emit_one(
                writer: var writer, path: child, brackets: "[", table: table
            )
            case ArrayValue(elements):
                if section_kind(entry.value.clone()) == 2:
                    for table in table_items(elements.clone()): emit_one(
                        writer: var writer, path: child.clone(), brackets: "[[",
                        table: table
                    )
            case _: ()

def datetimes_valid(value: TomlValue) -> Bool:
    match value:
        case DateTimeValue(text): return datetime_valid(text)
        case ArrayValue(values):
            for item in values:
                if not datetimes_valid(item): return False
            return True
        case TableValue(values):
            for entry in values.entries():
                if not datetimes_valid(entry.value.clone()): return False
            return True
        case _: return True

# Serializes a table value as a TOML document. Tables and arrays of tables use headers; other values are written inline.
export def stringify(
    value: TomlValue,
    max_bytes: Optional[Int] = none
) -> Result[String, TomlError]:
    if let limit = max_bytes:
        if limit < 0: return error(TomlError.InvalidInput)

    let root = match value:
        case TableValue(values): values.clone()
        case _: return error(TomlError.InvalidInput)

    if not datetimes_valid(value): return error(TomlError.InvalidInput)

    var writer = Writer(StringBuilder(), started: False)
    emit_table(var writer, [], root)

    let text = writer.out.build()
    if not within(text.byte_length(), max_bytes): return error(TomlError.LimitExceeded)

    return ok(text)
