# TOML 1.0 parser implemented in Manuscript.
import {parse_int, parse_float} from "@std/numbers.ms"
import {from_scalars, StringBuilder} from "@std/string.ms"
import {log, sqrt} from "@std/math.ms"

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

type Reader:
    chars: List[String]
    pos: Int
    line: Int
    column: Int
    limits: TomlLimits
    values: Int

type Table:
    entries: Map[String, Node]
    explicit: Bool
    dotted: Bool
    sealed: Bool

type Node:
    case Leaf(value: TomlValue)
    case TableNode(table: Table)
    case ArrayNode(values: List[Node])
    case TableArray(tables: List[Table])

fn table(explicit: Bool, dotted: Bool) Table:
    return Table(
        entries: Map[String, Node](),
        explicit: explicit,
        dotted: dotted,
        sealed: false
    )

fn peek(reader: Reader) String:
    return reader.chars.at(reader.pos).get("")

fn ahead(reader: Reader, offset: Int) String:
    return reader.chars.at(reader.pos + offset).get("")

fn advance(reader: Reader) String:
    let c = peek(reader)
    if c == "": return c

    reader.pos += 1

    if c == "\n":
        reader.line += 1
        reader.column = 1
    else:
        reader.column += 1

    return c

fn invalid(reader: Reader, reason: String) TomlError:
    return TomlError.InvalidData(
        line: reader.line,
        column: reader.column,
        reason: reason
    )

fn space(reader: Reader, multiline: Bool) Unit:
    while true:
        let c = peek(reader)

        if (c == " " or c == "\t" or (multiline and c == "\n")):
            advance(reader)
        else if multiline and c == "#":
            while peek(reader) != "" and peek(reader) != "\n": advance(reader)
        else:
            break

fn within(value: Int, limit: Optional[Int]) Bool:
    if let maximum = limit:
        return value <= maximum

    return true

fn allocate(reader: Reader) Result[Unit, TomlError]:
    reader.values += 1
    if not within(reader.values, reader.limits.max_values): return error(
        TomlError.LimitExceeded
    )

    return ok(unit)

fn budget(reader: Reader, depth: Int) Result[Unit, TomlError]:
    if not within(depth, reader.limits.max_depth): return error(TomlError.LimitExceeded)

    return ok(unit)

# Basic and literal strings, including multiline delimiters and escaped newline folding.
fn string_value(reader: Reader, key: Bool) Result[String, TomlError]:
    let quote = advance(reader)
    var multiline = false

    if (not key and peek(reader) == quote and ahead(reader, 1) == quote):
        advance(reader)
        advance(reader)
        multiline = true
        if peek(reader) == "\n": advance(reader)

    # Append through a builder: per-character concatenation is quadratic on long strings.
    let result = StringBuilder()

    while true:
        let c = advance(reader)
        if c == "": return error(invalid(reader, "unterminated string"))

        if c == quote:
            if not multiline: return ok(result.freeze())

            if peek(reader) == quote and ahead(reader, 1) == quote:
                advance(reader)
                advance(reader)
                var extra = 0

                while peek(reader) == quote and extra < 2:
                    result.append(advance(reader))
                    extra += 1

                return ok(result.freeze())

            result.append(c)
            continue

        let code = c.scalar_at(0).get()
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
            while peek(reader) == " " or peek(reader) == "\t": advance(reader)
            if advance(reader) != "\n": return error(
                invalid(reader, "expected escaped newline")
            )

            while (peek(reader) == " " or peek(reader) == "\t" or peek(reader) == "\n"): advance(
                reader
            )
            continue

        let escaped = advance(reader)

        if escaped == "b": result.append("\u{8}")
        else if escaped == "t": result.append("\t")
        else if escaped == "n": result.append("\n")
        else if escaped == "f": result.append("\u{c}")
        else if escaped == "r": result.append("\r")
        else if escaped == "\"" or escaped == "\\": result.append(escaped)
        else if escaped == "u" or escaped == "U":
            var count = 4
            if escaped == "U": count = 8
            var hex = ""

            while count > 0:
                let digit = advance(reader)
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

fn key_path(reader: Reader) Result[List[String], TomlError]:
    let keys: List[String] = []

    while true:
        space(reader, multiline: false)
        var key = ""

        if peek(reader) == "\"" or peek(reader) == "'":
            key = try string_value(reader, key: true)
        else:
            while (
                peek(reader) != ""
                and "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(
                    peek(reader)
                )
            ):
                key = key.concat(advance(reader))
            if key == "": return error(invalid(reader, "expected key"))

        keys.append(key)
        space(reader, multiline: false)
        if peek(reader) != ".": return ok(keys)

        advance(reader)

fn child(
    reader: Reader,
    parent: Table,
    key: String,
    dotted: Bool
) Result[Table, TomlError]:
    if parent.sealed: return error(invalid(reader, "inline table is closed"))

    let existing = parent.entries.get(key)

    if existing.is_none():
        try allocate(reader)
        let created = table(explicit: false, dotted)
        parent.entries.add(key, Node.TableNode(created))
        return ok(created)

    let node = existing.get()

    match node:
        TableNode(value):
            if value.sealed: return error(invalid(reader, "inline table is closed"))
            if dotted and value.explicit: return error(
                invalid(reader, "dotted key extends an explicit table")
            )

            return ok(value)
        TableArray(tables):
            if dotted: return error(invalid(reader, "dotted key extends a table array"))

            return ok(tables.last().get())
        _: return error(invalid(reader, "key is already a value"))

fn append_table(
    reader: Reader,
    parent: Table,
    key: String,
    next: Table
) Result[Unit, TomlError]:
    let existing = parent.entries.get(key)

    if existing.is_none():
        try allocate(reader)
        parent.entries.add(key, Node.TableArray([next]))
        return ok(unit)

    let node = existing.get()

    match node:
        TableArray(tables):
            tables.append(next)
            return ok(unit)
        _: return error(invalid(reader, "table array conflicts with value"))

fn assign(
    reader: Reader,
    parent: Table,
    keys: List[String],
    value: Node
) Result[Unit, TomlError]:
    var current = parent
    var index = 0

    while index < keys.length() - 1:
        current = try child(
            reader: reader,
            parent: current,
            key: (keys.at(index).get()),
            dotted: true
        )
        index += 1

    let key = keys.last().get()
    if current.sealed or current.entries.contains(key): return error(
        invalid(reader, "duplicate or closed key")
    )

    current.entries.add(key, value)
    return ok(unit)

fn seal(value: Node) Unit:
    match value:
        TableNode(table):
            table.sealed = true
            for entry in table.entries: seal(entry.value)
        ArrayNode(values):
            for item in values: seal(item)
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

    let clean = text.replace("_", "", text.byte_length())
    return clean == "0" or not clean.starts_with("0")

fn date_number(text: String, minimum: Int, maximum: Int) Bool:
    if not digits(text, "0123456789") or text.contains("_"): return false
    if let value = parse_int(text, 10):
        return value >= minimum and value <= maximum

    return false

fn date_valid(text: String) Bool:
    if (
        text.scalar_length() != 10
        or text.at(4).get("") != "-"
        or text.at(7).get("") != "-"
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
        or text.at(2).get("") != ":"
        or text.at(5).get("") != ":"
    ): return false
    if not date_number(text.slice(0, 2).get(""), 0, 23): return false
    if not date_number(text.slice(3, 5).get(""), 0, 59): return false
    if not date_number(text.slice(6, 8).get(""), 0, 60): return false
    if text.scalar_length() == 8: return true

    let fraction = text.slice(9, text.scalar_length()).get("")
    return (
        text.at(8).get("") == "."
        and decimal_digits(fraction)
        and not fraction.contains("_")
    )

fn datetime_valid(text: String) Bool:
    if date_valid(text): return true
    if time_valid(text): return true
    if (text.scalar_length() < 19 or not date_valid((text.slice(0, 10).get("")))): return false

    let separator = text.at(10).get("")
    if (separator != "T" and separator != "t" and separator != " "): return false

    var rest = text.slice(11, text.scalar_length()).get("")

    if rest.ends_with("Z") or rest.ends_with("z"):
        rest = rest.slice(0, rest.scalar_length() - 1).get("")
    else if rest.contains("+") or rest.contains("-"):
        var index = rest.index_of("+").get(-1)
        if index < 0: index = rest.index_of("-").get(-1)
        let zone = rest.slice(index + 1, rest.scalar_length()).get("")
        if zone.scalar_length() != 5 or zone.at(2).get("") != ":": return false
        if not date_number(zone.slice(0, 2).get(""), 0, 23): return false
        if not date_number(zone.slice(3, 5).get(""), 0, 59): return false

        rest = rest.slice(0, index).get("")

    return time_valid(rest)

fn scalar(reader: Reader, text: String) Result[Node, TomlError]:
    if text == "true": return ok(Node.Leaf(TomlValue.BoolValue(true)))
    if text == "false": return ok(Node.Leaf(TomlValue.BoolValue(false)))
    if datetime_valid(text): return ok(Node.Leaf(TomlValue.DateTimeValue(text)))

    var clean = text
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
                clean.slice(2, clean.scalar_length()).get(""),
                alphabet
            )
        ):
            return error(invalid(reader, "invalid integer"))
        if let value = parse_int(
            (
                clean
                .slice(2, clean.scalar_length())
                .get("")
                .replace("_", "", text.byte_length())
            ),
            radix
        ): return ok(Node.Leaf(TomlValue.IntValue(value)))

        return error(invalid(reader, "integer out of range"))

    # Bare words such as True, yes, or abc are not numbers, even when they
    # contain an e.
    if (
        clean != "inf"
        and clean != "nan"
        and not "0123456789".contains(clean.at(0).get("x"))
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
                var exponent = parts.at(1).get()
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
            if fraction.length() == 2 and not decimal_digits(fraction.at(1).get()): return error(
                invalid(reader, "invalid fraction")
            )

        if clean == "inf":
            var infinity = -log(0.0)
            if text.starts_with("-"): infinity = -infinity
            return ok(Node.Leaf(TomlValue.FloatValue(infinity)))

        if clean == "nan": return ok(Node.Leaf(TomlValue.FloatValue(sqrt((-1.0)))))

        let number = text.replace("_", "", text.byte_length())
        if let value = parse_float(number): return ok(
            Node.Leaf(TomlValue.FloatValue(value))
        )

        return error(invalid(reader, "float out of range"))

    if not decimal_part(clean): return error(invalid(reader, "invalid value"))
    if let value = parse_int(text.replace("_", "", text.byte_length()), 10): return ok(
        Node.Leaf(TomlValue.IntValue(value))
    )

    return error(invalid(reader, "integer out of range"))

fn read_value(reader: Reader, depth: Int) Result[Node, TomlError]:
    try allocate(reader)
    try budget(reader, depth)
    space(reader, multiline: false)
    let c = peek(reader)
    if c == "\"" or c == "'": return ok(
        Node.Leaf(TomlValue.StringValue(try string_value(reader, key: false)))
    )

    if c == "[":
        advance(reader)
        let values: List[Node] = []
        space(reader, multiline: true)

        while peek(reader) != "]":
            values.append(try read_value(reader, depth + 1))
            space(reader, multiline: true)
            if peek(reader) == "]": break
            if advance(reader) != ",": return error(
                invalid(reader, "expected array comma")
            )

            space(reader, multiline: true)

        advance(reader)
        return ok(Node.ArrayNode(values))

    if c == "\{":
        advance(reader)
        let result = table(explicit: true, dotted: false)
        space(reader, multiline: false)

        if peek(reader) != "\}":
            while true:
                let keys = try key_path(reader)
                if advance(reader) != "=": return error(
                    invalid(reader, "expected equals")
                )

                let value = try read_value(reader, depth + keys.length())
                try assign(reader: reader, parent: result, keys: keys, value: value)
                space(reader, multiline: false)
                if peek(reader) == "\}": break
                if advance(reader) != ",": return error(
                    invalid(reader, "expected inline table comma")
                )

        advance(reader)
        let node = Node.TableNode(result)
        seal(node)
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
        and peek(reader) != "\}"
        and peek(reader) != " "
    ):
        text = text.concat(advance(reader))

    # A space may separate date and time, but otherwise ends the token.
    if (date_valid(text) and peek(reader) == " " and ahead(reader, 3) == ":"):
        text = text.concat(advance(reader))
        while (
            peek(reader) != ""
            and peek(reader) != "\n"
            and peek(reader) != " "
            and peek(reader) != "\t"
            and peek(reader) != "#"
            and peek(reader) != ","
            and peek(reader) != "]"
            and peek(reader) != "\}"
        ):
            text = text.concat(advance(reader))

    # Report token errors where the token starts, not where it ended.
    let end_line = reader.line
    let end_column = reader.column
    reader.line = start_line
    reader.column = start_column
    let result = scalar(reader, text)
    reader.line = end_line
    reader.column = end_column
    return result

fn materialize(reader: Reader, node: Node, depth: Int) Result[TomlValue, TomlError]:
    try budget(reader, depth)
    reader.values += 1
    if not within(reader.values, reader.limits.max_values): return error(
        TomlError.LimitExceeded
    )

    match node:
        Leaf(value): return ok(value)
        TableNode(table):
            let entries = Map[String, TomlValue]()
            for entry in table.entries:
                entries.add(
                    entry.key,
                    try materialize(
                        reader,
                        entry.value,
                        (depth + 1)
                    )
                )
            return ok(TomlValue.TableValue(entries))
        ArrayNode(values):
            let result: List[TomlValue] = []
            for value in values: result.append(
                try materialize(reader, value, (depth + 1))
            )
            return ok(TomlValue.ArrayValue(result))
        TableArray(tables):
            let result: List[TomlValue] = []
            for table in tables: result.append(
                try materialize(
                    reader,
                    Node.TableNode(table),
                    (depth + 1)
                )
            )
            return ok(TomlValue.ArrayValue(result))

# Parses a TOML document into a table value and reports source line and column on invalid input.
export fn parse(
    text: String,
    limits: Optional[TomlLimits] = none
) Result[TomlValue, TomlError]:
    var options = TomlLimits()
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
    let normalized = text.replace("\r\n", "\n", text.byte_length())
    var scan_line = 1
    var scan_column = 1

    for code in normalized.scalar_values():
        if code == 13: return error(
            TomlError.InvalidData(
                line: scan_line,
                column: scan_column,
                reason: "bare carriage return"
            )
        )
        if (code < 32 and code != 9 and code != 10) or code == 127: return error(
            TomlError.InvalidData(
                line: scan_line,
                column: scan_column,
                reason: "invalid control character"
            )
        )

        if code == 10:
            scan_line += 1
            scan_column = 1
        else: scan_column += 1

    let reader = Reader(
        chars: normalized.split(""),
        pos: 0,
        line: 1,
        column: 1,
        limits: options,
        values: 0
    )
    try allocate(reader)
    let root = table(explicit: true, dotted: false)
    var current = root
    var current_depth = 1

    while true:
        space(reader, multiline: true)
        if peek(reader) == "": break

        if peek(reader) == "[":
            advance(reader)
            var array = false

            if peek(reader) == "[":
                advance(reader)
                array = true

            let keys = try key_path(reader)
            if advance(reader) != "]" or (array and advance(reader) != "]"): return error(
                invalid(reader, "expected closing table bracket")
            )

            var parent = root
            var index = 0

            while index < keys.length() - 1:
                parent = try child(
                    reader: reader,
                    parent: parent,
                    key: (keys.at(index).get()),
                    dotted: false
                )
                index += 1

            let key = keys.last().get()
            if parent.sealed: return error(invalid(reader, "inline table is closed"))

            if array:
                try allocate(reader)
                let next = table(explicit: true, dotted: false)
                try append_table(reader: reader, parent: parent, key: key, next: next)
                current = next
            else:
                current = try child(
                    reader: reader,
                    parent: parent,
                    key: key,
                    dotted: false
                )
                if current.explicit or current.dotted: return error(
                    invalid(reader, "table already defined")
                )

                current.explicit = true

            current_depth = keys.length() + 1
            if array: current_depth += 1
            try budget(reader, current_depth)
        else:
            let keys = try key_path(reader)
            if advance(reader) != "=": return error(invalid(reader, "expected equals"))

            let value = try read_value(reader, (current_depth + keys.length()))
            try assign(reader: reader, parent: current, keys: keys, value: value)

        space(reader, multiline: false)
        if peek(reader) == "#":
            while peek(reader) != "" and peek(reader) != "\n": advance(reader)
        if peek(reader) != "" and advance(reader) != "\n": return error(
            invalid(reader, "unexpected trailing text")
        )

    reader.values = 0
    return materialize(reader, Node.TableNode(root), 1)

type Writer:
    out: StringBuilder
    started: Bool

fn hex4(code: Int) String:
    var digits = code.to_string_radix(16)
    while digits.length() < 4: digits = "0".concat(digits)
    return digits

fn quote_text(text: String) String:
    let result = StringBuilder()
    result.append("\"")

    for c in text.chars():
        let code = c.scalar_at(0).get()

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
    return result.freeze()

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
            let parts: List[String] = []
            for item in values: parts.append(inline_value(item))
            return "[".concat(parts.join(", ")).concat("]")
        TableValue(values):
            let parts: List[String] = []
            for entry in values.entries(): parts.append(
                format_key(entry.key).concat(" = ").concat(
                    inline_value(entry.value)
                )
            )
            if parts.is_empty(): return "\{\}"

            return "\{ ".concat(parts.join(", ")).concat(" \}")

fn table_items(values: List[TomlValue]) List[Map[String, TomlValue]]:
    let tables: List[Map[String, TomlValue]] = []

    for item in values:
        match item:
            TableValue(table): tables.append(table)
            _: return []

    return tables

fn dotted(path: List[String]) String:
    let parts: List[String] = []
    for key in path: parts.append(format_key(key))
    return parts.join(".")

fn emit_header(writer: Writer, header: String) Unit:
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
                and table_items(elements).length() == elements.length()
            ): return 2

            return 0
        _: return 0

fn emit_one(
    writer: Writer,
    path: List[String],
    brackets: String,
    table: Map[String, TomlValue]
) Unit:
    if brackets == "[[": emit_header(writer, "[[".concat(dotted(path)).concat("]]"))
    else: emit_header(writer, "[".concat(dotted(path)).concat("]"))

    emit_table(writer, path, table)

fn emit_table(writer: Writer, path: List[String], values: Map[String, TomlValue]) Unit:
    for entry in values.entries():
        if section_kind(entry.value) == 0: (
            writer
            .out
            .append(
                (
                    format_key(entry.key)
                    .concat(" = ")
                    .concat(inline_value(entry.value))
                    .concat("\n")
                )
            )
        )

    for entry in values.entries():
        let child = path.clone()
        child.append(entry.key)

        match entry.value:
            TableValue(table): emit_one(
                writer: writer,
                path: child,
                brackets: "[",
                table: table
            )
            ArrayValue(elements):
                if section_kind(entry.value) == 2:
                    for table in table_items(elements): emit_one(
                        writer: writer,
                        path: child,
                        brackets: "[[",
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
                if not datetimes_valid(entry.value): return false
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
        TableValue(values): values
        _: return error(TomlError.InvalidInput)

    if not datetimes_valid(value): return error(TomlError.InvalidInput)

    let writer = Writer(StringBuilder(), started: false)
    emit_table(writer, [], root)
    let text = writer.out.freeze()
    if not within(text.byte_length(), max_bytes): return error(TomlError.LimitExceeded)

    return ok(text)
