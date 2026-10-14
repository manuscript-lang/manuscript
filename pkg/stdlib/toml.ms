# TOML 1.0 parser implemented in Manuscript.
import {List, Map} from "@std/collections.ms"
import {parse_int, parse_float} from "@std/numbers.ms"
import from_scalars from "@std/string.ms"
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
    # One of the supplied byte, depth or value-count limits is negative.
    case InvalidInput
    # Invalid syntax, keys, value forms, numeric ranges, date/time text or cyclic serialization values.
    case InvalidData(
        # One-based line of the invalid token, or zero for an invalid serialization value.
        line: Int,
        # One-based Unicode scalar column after normalization, or zero for serialization errors.
        column: Int,
        # Diagnostic describing the rejected TOML syntax, value or cyclic graph.
        reason: String
    )
    # Input/output bytes, nesting or parsed/serialized value counts exceed a supplied budget.
    case LimitExceeded

# Optional byte, nesting-depth, and value-count limits for TOML parsing and serialization.
export type TomlLimits:
    # Maximum UTF-8 input bytes before normalization or stringify output bytes; none adds no budget.
    max_bytes: Optional[Int]
    # Maximum value depth, including scalar leaves and implicit tables, with the root at one.
    max_depth: Optional[Int]
    # Maximum containers and leaves, excluding keys; checked during parsing, materialization and stringify.
    max_values: Optional[Int]

impl Error for TomlError:
    # Formats the source line, scalar column and parser reason for a malformed document.
    fn message() -> String:
        match self:
            InvalidInput: return "invalid TOML limits"
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

fn table(explicit: Bool, dotted: Bool) -> Table:
    return Table(
        entries: Map[String, Node](),
        explicit: explicit,
        dotted: dotted,
        sealed: false
    )

fn peek(reader: Reader) -> String:
    return reader.chars.at(reader.pos).unwrap_or("")

fn ahead(reader: Reader, offset: Int) -> String:
    return reader.chars.at(reader.pos + offset).unwrap_or("")

fn advance(reader: Reader) -> String:
    let c = peek(reader)
    if c == "": return c

    reader.pos = reader.pos + 1

    if c == "\n":
        reader.line = reader.line + 1
        reader.column = 1
    else:
        reader.column = reader.column + 1

    return c

fn invalid(reader: Reader, reason: String) -> TomlError:
    return TomlError.InvalidData(
        line: reader.line,
        column: reader.column,
        reason: reason
    )

fn space(reader: Reader, multiline: Bool) -> Unit:
    while true:
        let c = peek(reader)

        if (
            c == " "
            or c == "\t"
            or (multiline and c == "\n")
        ):
            advance(reader)
        else if multiline and c == "#":
            while peek(reader) != "" and peek(reader) != "\n": advance(reader)
        else:
            break

fn within(value: Int, limit: Optional[Int]) -> Bool:
    match limit:
        none: return true
        some(maximum): return value <= maximum

fn allocate(reader: Reader) -> Result[Unit, TomlError]:
    reader.values = reader.values + 1
    if not within(value: reader.values, limit: reader.limits.max_values): return error(
        TomlError.LimitExceeded
    )

    return ok(unit)

fn budget(reader: Reader, depth: Int) -> Result[Unit, TomlError]:
    if not within(value: depth, limit: reader.limits.max_depth): return error(
        TomlError.LimitExceeded
    )

    return ok(unit)

# Basic and literal strings, including multiline delimiters and escaped newline folding.
fn string_value(reader: Reader, key: Bool) -> Result[String, TomlError]:
    let quote = advance(reader)
    var multiline = false

    if (
        not key
        and peek(reader) == quote
        and ahead(reader: reader, offset: 1) == quote
    ):
        advance(reader)
        advance(reader)
        multiline = true

        if peek(reader) == "\n": advance(reader)

    var result = ""

    while true:
        let c = advance(reader)
        if c == "": return error(
            invalid(reader: reader, reason: "unterminated string")
        )

        if c == quote:
            if not multiline: return ok(result)

            if peek(reader) == quote and ahead(reader: reader, offset: 1) == quote:
                advance(reader)
                advance(reader)
                var extra = 0

                while peek(reader) == quote and extra < 2:
                    result = result.concat(advance(reader))
                    extra = extra + 1

                return ok(result)

            result = result.concat(c)
            continue

        let code = c.scalar_at(0).unwrap()
        if (
            code < 32
            and c != "\t"
            and not (multiline and c == "\n")
        ) or code == 127:
            return error(
                invalid(
                    reader: reader,
                    reason: "control character in string"
                )
            )

        if c != "\\" or quote == "'":
            result = result.concat(c)
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
                invalid(
                    reader: reader,
                    reason: "expected escaped newline"
                )
            )

            while (
                peek(reader) == " "
                or peek(reader) == "\t"
                or peek(reader) == "\n"
            ): advance(reader)

            continue

        let escaped = advance(reader)

        if escaped == "b": result = result.concat("\u{8}")
        else if escaped == "t": result = result.concat("\t")
        else if escaped == "n": result = result.concat("\n")
        else if escaped == "f": result = result.concat("\u{c}")
        else if escaped == "r": result = result.concat("\r")
        else if escaped == "\"" or escaped == "\\": result = result.concat(escaped)
        else if escaped == "u" or escaped == "U":
            var count = 4

            if escaped == "U": count = 8

            var hex = ""

            while count > 0:
                let digit = advance(reader)
                if digit == "" or not "0123456789abcdefABCDEF".contains(digit):
                    return error(
                        invalid(
                            reader: reader,
                            reason: "invalid Unicode escape"
                        )
                    )

                hex = hex.concat(digit)
                count = count - 1

            let scalar = match parse_int(text: hex, radix: 16):
                error(_): return error(
                    invalid(
                        reader: reader,
                        reason: "invalid Unicode escape"
                    )
                )

                ok(scalar): scalar

            match from_scalars([scalar]):
                error(_): return error(
                    invalid(
                        reader: reader,
                        reason: "invalid Unicode scalar"
                    )
                )
                ok(text): result = result.concat(text)

        else:
            return error(
                invalid(
                    reader: reader,
                    reason: "invalid string escape"
                )
            )

fn key_path(reader: Reader) -> Result[List[String], TomlError]:
    let keys: List[String] = []

    while true:
        space(reader: reader, multiline: false)
        var key = ""

        if peek(reader) == "\"" or peek(reader) == "'":
            key = try string_value(reader: reader, key: true)
        else:
            while (
                peek(reader) != ""
                and "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(
                    peek(reader)
                )
            ):
                key = key.concat(advance(reader))

            if key == "": return error(
                invalid(reader: reader, reason: "expected key")
            )

        keys.append(key)
        space(reader: reader, multiline: false)
        if peek(reader) != ".": return ok(keys)

        advance(reader)

fn child(
    reader: Reader,
    parent: Table,
    key: String,
    dotted: Bool
) -> Result[Table, TomlError]:
    if parent.sealed: return error(
        invalid(reader: reader, reason: "inline table is closed")
    )

    let node = match parent.entries.get(key):
        none:
            let allocated = try allocate(reader)
            let created = table(explicit: false, dotted: dotted)
            parent.entries.add(
                key: key,
                value: Node.TableNode(created)
            )
            return ok(created)

        some(node): node

    match node:
        TableNode(value):
            if value.sealed: return error(
                invalid(
                    reader: reader,
                    reason: "inline table is closed"
                )
            )
            if dotted and value.explicit: return error(
                invalid(
                    reader: reader,
                    reason: "dotted key extends an explicit table"
                )
            )

            return ok(value)

        TableArray(tables):
            if dotted: return error(
                invalid(
                    reader: reader,
                    reason: "dotted key extends a table array"
                )
            )

            return ok(tables.last().unwrap())

        _: return error(
            invalid(
                reader: reader,
                reason: "key is already a value"
            )
        )

fn append_table(
    reader: Reader,
    parent: Table,
    key: String,
    next: Table
) -> Result[Unit, TomlError]:
    let node = match parent.entries.get(key):
        none:
            let allocated_array = try allocate(reader)
            parent.entries.add(
                key: key,
                value: Node.TableArray([next])
            )
            return ok(unit)
        some(node): node

    match node:
        TableArray(tables):
            tables.append(next)
            return ok(unit)
        _: return error(
            invalid(
                reader: reader,
                reason: "table array conflicts with value"
            )
        )

fn assign(
    reader: Reader,
    parent: Table,
    keys: List[String],
    value: Node
) -> Result[Unit, TomlError]:
    var current = parent
    var index = 0

    while index < keys.length() - 1:
        current = try child(
            reader: reader,
            parent: current,
            key: (keys.at(index).unwrap()),
            dotted: true
        )
        index = index + 1

    let key = keys.last().unwrap()
    if current.sealed or current.entries.contains(key): return error(
        invalid(reader: reader, reason: "duplicate or closed key")
    )

    current.entries.add(key: key, value: value)
    return ok(unit)

fn seal(value: Node) -> Unit:
    match value:
        TableNode(table):
            table.sealed = true

            for entry in table.entries: seal(entry.value)

        ArrayNode(values):
            for item in values: seal(item)

        _: return unit

fn digits(text: String, alphabet: String) -> Bool:
    if text == "": return false

    var previous = false

    for c in text.split(separator: ""):
        if c == "_":
            if not previous: return false

            previous = false
        else:
            if not alphabet.contains(c): return false

            previous = true

    return previous

fn decimal_digits(text: String) -> Bool:
    return digits(text: text, alphabet: "0123456789")

fn decimal_part(text: String) -> Bool:
    if not decimal_digits(text): return false

    let clean = text.replace(
        old: "_",
        new: "",
        max_replacements: text.byte_length()
    )
    return clean == "0" or not clean.starts_with("0")

fn date_number(text: String, minimum: Int, maximum: Int) -> Bool:
    if not digits(text: text, alphabet: "0123456789") or text.contains("_"): return false

    match parse_int(text: text, radix: 10):
        error(_): return false
        ok(value): return value >= minimum and value <= maximum

fn date_valid(text: String) -> Bool:
    if (
        text.scalar_length() != 10
        or text.at(4).unwrap_or("") != "-"
        or text.at(7).unwrap_or("") != "-"
    ): return false

    let year = text.slice(start: 0, end: 4).unwrap_or("")
    let month = text.slice(start: 5, end: 7).unwrap_or("")
    let day = text.slice(start: 8, end: 10).unwrap_or("")
    if (
        not date_number(text: year, minimum: 0, maximum: 9999)
        or not date_number(text: month, minimum: 1, maximum: 12)
    ): return false

    let m = month.parse_int().unwrap()
    var maximum = 31

    if (
        m == 4
        or m == 6
        or m == 9
        or m == 11
    ): maximum = 30

    if m == 2:
        maximum = 28
        let y = year.parse_int().unwrap()

        if y % 4 == 0 and (y % 100 != 0 or y % 400 == 0): maximum = 29

    return date_number(text: day, minimum: 1, maximum: maximum)

fn time_valid(text: String) -> Bool:
    if (
        text.scalar_length() < 8
        or text.at(2).unwrap_or("") != ":"
        or text.at(5).unwrap_or("") != ":"
    ): return false
    if not date_number(
        text: text.slice(start: 0, end: 2).unwrap_or(""),
        minimum: 0,
        maximum: 23
    ): return false
    if not date_number(
        text: text.slice(start: 3, end: 5).unwrap_or(""),
        minimum: 0,
        maximum: 59
    ): return false
    if not date_number(
        text: text.slice(start: 6, end: 8).unwrap_or(""),
        minimum: 0,
        maximum: 60
    ): return false
    if text.scalar_length() == 8: return true

    let fraction = text.slice(
        start: 9,
        end: text.scalar_length()
    ).unwrap_or("")
    return (
        text.at(8).unwrap_or("") == "."
        and decimal_digits(fraction)
        and not fraction.contains("_")
    )

fn datetime_valid(text: String) -> Bool:
    if date_valid(text): return true
    if time_valid(text): return true
    if (
        text.scalar_length() < 19
        or not date_valid((text.slice(start: 0, end: 10).unwrap_or("")))
    ): return false

    let separator = text.at(10).unwrap_or("")
    if (
        separator != "T"
        and separator != "t"
        and separator != " "
    ): return false

    var rest = text.slice(
        start: 11,
        end: text.scalar_length()
    ).unwrap_or("")

    if rest.ends_with("Z") or rest.ends_with("z"):
        rest = rest.slice(start: 0, end: rest.scalar_length() - 1).unwrap_or("")
    else if rest.contains("+") or rest.contains("-"):
        var index = rest.index_of("+").unwrap_or(-1)

        if index < 0: index = rest.index_of("-").unwrap_or(-1)

        let zone = rest.slice(
            start: index + 1,
            end: rest.scalar_length()
        ).unwrap_or("")
        if zone.scalar_length() != 5 or zone.at(2).unwrap_or("") != ":": return false
        if not date_number(
            text: zone.slice(start: 0, end: 2).unwrap_or(""),
            minimum: 0,
            maximum: 23
        ): return false
        if not date_number(
            text: zone.slice(start: 3, end: 5).unwrap_or(""),
            minimum: 0,
            maximum: 59
        ): return false

        rest = rest.slice(start: 0, end: index).unwrap_or("")

    return time_valid(rest)

fn scalar(reader: Reader, text: String) -> Result[Node, TomlError]:
    if text == "true": return ok(
        Node.Leaf(TomlValue.BoolValue(true))
    )
    if text == "false": return ok(
        Node.Leaf(TomlValue.BoolValue(false))
    )
    if datetime_valid(text): return ok(
        Node.Leaf(TomlValue.DateTimeValue(text))
    )

    var clean = text
    var signed = false

    if clean.starts_with("+") or clean.starts_with("-"):
        signed = true
        clean = clean.slice(
            start: 1,
            end: clean.scalar_length()
        ).unwrap_or("")

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
                text: clean.slice(
                    start: 2,
                    end: clean.scalar_length()
                ).unwrap_or(""),
                alphabet: alphabet
            )
        ):
            return error(invalid(reader: reader, reason: "invalid integer"))

        match parse_int(
            text: (
                clean
                .slice(
                    start: 2,
                    end: clean.scalar_length()
                )
                .unwrap_or("")
                .replace(
                    old: "_",
                    new: "",
                    max_replacements: text.byte_length()
                )
            ),
            radix: radix
        ):
            ok(value): return ok(
                Node.Leaf(
                    TomlValue.IntValue(value)
                )
            )
            error(_): return error(
                invalid(
                    reader: reader,
                    reason: "integer out of range"
                )
            )

    # Bare words such as True, yes, or abc are not numbers, even when they
    # contain an e.
    if (
        clean != "inf"
        and clean != "nan"
        and not "0123456789".contains(clean.at(0).unwrap_or("x"))
    ): return error(invalid(reader: reader, reason: "invalid value"))

    if (
        clean == "inf"
        or clean == "nan"
        or clean.contains(".")
        or clean.contains("e")
        or clean.contains("E")
    ):
        if clean != "inf" and clean != "nan":
            let parts = clean.lower().split(separator: "e")
            if parts.length() > 2: return error(
                invalid(reader: reader, reason: "invalid float")
            )

            if parts.length() == 2:
                var exponent = parts.at(1).unwrap()

                if exponent.starts_with("+") or exponent.starts_with("-"): exponent = (
                    exponent
                    .slice(
                        start: 1,
                        end: exponent.scalar_length()
                    )
                    .unwrap_or("")
                )

                if not decimal_digits(exponent): return error(
                    invalid(
                        reader: reader,
                        reason: "invalid exponent"
                    )
                )

            let fraction = parts.first().unwrap().split(separator: ".")
            if fraction.length() > 2 or not decimal_part(fraction.first().unwrap()): return error(
                invalid(reader: reader, reason: "invalid float")
            )
            if fraction.length() == 2 and not decimal_digits(fraction.at(1).unwrap()): return error(
                invalid(
                    reader: reader,
                    reason: "invalid fraction"
                )
            )

        if clean == "inf":
            var infinity = -log(0.0)

            if text.starts_with("-"): infinity = -infinity

            return ok(
                Node.Leaf(
                    TomlValue.FloatValue(infinity)
                )
            )

        if clean == "nan": return ok(
            Node.Leaf(
                TomlValue.FloatValue(sqrt((-1.0)))
            )
        )

        let number = text.replace(
            old: "_",
            new: "",
            max_replacements: text.byte_length()
        )

        match parse_float(number):
            ok(value): return ok(
                Node.Leaf(
                    TomlValue.FloatValue(value)
                )
            )
            error(_): return error(
                invalid(
                    reader: reader,
                    reason: "float out of range"
                )
            )

    if not decimal_part(clean): return error(
        invalid(reader: reader, reason: "invalid value")
    )

    match parse_int(
        text: text.replace(
            old: "_",
            new: "",
            max_replacements: text.byte_length()
        ),
        radix: 10
    ):
        ok(value): return ok(
            Node.Leaf(TomlValue.IntValue(value))
        )
        error(_): return error(
            invalid(reader: reader, reason: "integer out of range")
        )

fn read_value(reader: Reader, depth: Int) -> Result[Node, TomlError]:
    let allocated = try allocate(reader)
    let checked_budget = try budget(reader: reader, depth: depth)
    space(reader: reader, multiline: false)
    let c = peek(reader)
    if c == "\"" or c == "'": return ok(
        Node.Leaf(
            TomlValue.StringValue(
                try string_value(reader: reader, key: false)
            )
        )
    )

    if c == "[":
        advance(reader)
        let values: List[Node] = []
        space(reader: reader, multiline: true)

        while peek(reader) != "]":
            values.append(try read_value(reader: reader, depth: depth + 1))
            space(reader: reader, multiline: true)
            if peek(reader) == "]": break
            if advance(reader) != ",": return error(
                invalid(
                    reader: reader,
                    reason: "expected array comma"
                )
            )

            space(reader: reader, multiline: true)

        advance(reader)
        return ok(Node.ArrayNode(values))

    if c == "\{":
        advance(reader)
        let result = table(explicit: true, dotted: false)
        space(reader: reader, multiline: false)

        if peek(reader) != "\}":
            while true:
                let keys = try key_path(reader)
                if advance(reader) != "=": return error(
                    invalid(
                        reader: reader,
                        reason: "expected equals"
                    )
                )

                let value = try read_value(reader: reader, depth: depth + keys.length())
                let assigned = try assign(
                    reader: reader,
                    parent: result,
                    keys: keys,
                    value: value
                )
                space(reader: reader, multiline: false)
                if peek(reader) == "\}": break
                if advance(reader) != ",": return error(
                    invalid(
                        reader: reader,
                        reason: "expected inline table comma"
                    )
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
    if (
        date_valid(text)
        and peek(reader) == " "
        and ahead(reader: reader, offset: 3) == ":"
    ):
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
    let result = scalar(reader: reader, text: text)
    reader.line = end_line
    reader.column = end_column
    return result

fn materialize(reader: Reader, node: Node, depth: Int) -> Result[TomlValue, TomlError]:
    let checked_budget = try budget(reader: reader, depth: depth)
    reader.values = reader.values + 1
    if not within(value: reader.values, limit: reader.limits.max_values): return error(
        TomlError.LimitExceeded
    )

    match node:
        Leaf(value): return ok(value)

        TableNode(table):
            let entries = Map[String, TomlValue]()

            for entry in table.entries:
                entries.add(
                    key: entry.key,
                    value: try materialize(
                        reader: reader,
                        node: entry.value,
                        depth: (depth + 1)
                    )
                )

            return ok(TomlValue.TableValue(entries))

        ArrayNode(values):
            let result: List[TomlValue] = []

            for value in values: result.append(
                try materialize(
                    reader: reader,
                    node: value,
                    depth: (depth + 1)
                )
            )

            return ok(TomlValue.ArrayValue(result))

        TableArray(tables):
            let result: List[TomlValue] = []

            for table in tables: result.append(
                try materialize(
                    reader: reader,
                    node: Node.TableNode(table),
                    depth: (depth + 1)
                )
            )

            return ok(TomlValue.ArrayValue(result))

# Parses a TOML document into a table value and reports source line and column on invalid input.
export fn parse(
    text: String,
    limits: Optional[TomlLimits] = none
) -> Result[TomlValue, TomlError]:
    var options = TomlLimits(max_bytes: none, max_depth: none, max_values: none)

    match limits:
        none: let ignored = unit
        some(value): options = value

    for limit in [options.max_bytes, options.max_depth, options.max_values]:
        match limit:
            none: let ignored = unit

            some(value):
                if value < 0: return error(TomlError.InvalidInput)

    if not within(
        value: text.byte_length(),
        limit: options.max_bytes
    ): return error(TomlError.LimitExceeded)

    # TOML permits CR only as part of CRLF. Report the first offending scalar
    # at its own line and column.
    let normalized = text.replace(
        old: "\r\n",
        new: "\n",
        max_replacements: text.byte_length()
    )
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

        if (
            code < 32
            and code != 9
            and code != 10
        ) or code == 127: return error(
            TomlError.InvalidData(
                line: scan_line,
                column: scan_column,
                reason: "invalid control character"
            )
        )

        if code == 10:
            scan_line = scan_line + 1
            scan_column = 1
        else: scan_column = scan_column + 1

    let reader = Reader(
        chars: normalized.split(separator: ""),
        pos: 0,
        line: 1,
        column: 1,
        limits: options,
        values: 0
    )
    let allocated_root = try allocate(reader)
    let root = table(explicit: true, dotted: false)
    var current = root
    var current_depth = 1

    while true:
        space(reader: reader, multiline: true)
        if peek(reader) == "": break

        if peek(reader) == "[":
            advance(reader)
            var array = false

            if peek(reader) == "[":
                advance(reader)
                array = true

            let keys = try key_path(reader)
            if advance(reader) != "]" or (array and advance(reader) != "]"): return error(
                invalid(
                    reader: reader,
                    reason: "expected closing table bracket"
                )
            )

            var parent = root
            var index = 0

            while index < keys.length() - 1:
                parent = try child(
                    reader: reader,
                    parent: parent,
                    key: (keys.at(index).unwrap()),
                    dotted: false
                )
                index = index + 1

            let key = keys.last().unwrap()
            if parent.sealed: return error(
                invalid(
                    reader: reader,
                    reason: "inline table is closed"
                )
            )

            if array:
                let allocated_table = try allocate(reader)
                let next = table(explicit: true, dotted: false)

                let appended = try append_table(
                    reader: reader,
                    parent: parent,
                    key: key,
                    next: next
                )

                current = next
            else:
                current = try child(
                    reader: reader,
                    parent: parent,
                    key: key,
                    dotted: false
                )
                if current.explicit or current.dotted: return error(
                    invalid(
                        reader: reader,
                        reason: "table already defined"
                    )
                )

                current.explicit = true

            current_depth = keys.length() + 1

            if array: current_depth = current_depth + 1

            let checked_budget = try budget(reader: reader, depth: current_depth)
        else:
            let keys = try key_path(reader)
            if advance(reader) != "=": return error(
                invalid(
                    reader: reader,
                    reason: "expected equals"
                )
            )

            let value = try read_value(
                reader: reader,
                depth: (current_depth + keys.length())
            )
            let assigned = try assign(
                reader: reader,
                parent: current,
                keys: keys,
                value: value
            )

        space(reader: reader, multiline: false)

        if peek(reader) == "#":
            while peek(reader) != "" and peek(reader) != "\n": advance(reader)

        if peek(reader) != "" and advance(reader) != "\n": return error(
            invalid(
                reader: reader,
                reason: "unexpected trailing text"
            )
        )

    reader.values = 0
    return materialize(
        reader: reader,
        node: Node.TableNode(root),
        depth: 1
    )

# Private serialization helpers are pinned native bindings, not public reference APIs.
fn same_list[T](left: List[T], right: List[T]) -> Bool:

fn same_table[T](left: Map[String, T], right: Map[String, T]) -> Bool:

type Writer:
    parts: List[String]
    bytes: Int
    values: Int
    limits: TomlLimits
    active_arrays: List[List[TomlValue]]
    active_tables: List[Map[String, TomlValue]]

fn write(writer: Writer, text: String) -> Result[Unit, TomlError]:
    let bytes = text.byte_length()

    match writer.limits.max_bytes:
        none: let ignored = unit
        some(maximum):
            if bytes > maximum - writer.bytes: return error(TomlError.LimitExceeded)

    writer.bytes = writer.bytes + bytes
    writer.parts.append(text)
    return ok(unit)

fn write_quoted(writer: Writer, text: String) -> Result[Unit, TomlError]:
    let opening = try write(writer: writer, text: "\"")

    for code in text.scalar_values():
        var escaped = from_scalars([code]).unwrap()

        if code == 34: escaped = "\\\""
        else if code == 92: escaped = "\\\\"
        else if code == 8: escaped = "\\b"
        else if code == 9: escaped = "\\t"
        else if code == 10: escaped = "\\n"
        else if code == 12: escaped = "\\f"
        else if code == 13: escaped = "\\r"
        else if code < 32 or code == 127:
            var digits = code.to_string(radix: 16)

            while digits.scalar_length() < 4: digits = "0{digits}"

            escaped = "\\u{digits}"

        let written = try write(writer: writer, text: escaped)

    return write(writer: writer, text: "\"")

fn write_count(writer: Writer, depth: Int) -> Result[Unit, TomlError]:
    if not within(value: depth, limit: writer.limits.max_depth): return error(
        TomlError.LimitExceeded
    )

    writer.values = writer.values + 1
    if not within(value: writer.values, limit: writer.limits.max_values): return error(
        TomlError.LimitExceeded
    )

    return ok(unit)

fn write_value(writer: Writer, value: TomlValue, depth: Int) -> Result[Unit, TomlError]:
    let counted = try write_count(writer: writer, depth: depth)

    match value:
        StringValue(text): return write_quoted(writer: writer, text: text)
        IntValue(number): return write(
            writer: writer,
            text: number.to_string(radix: 10)
        )
        FloatValue(number):
            if number.is_nan(): return write(writer: writer, text: "nan")

            if not number.is_finite():
                if number < 0.0: return write(writer: writer, text: "-inf")

                return write(writer: writer, text: "inf")

            var text = number.to_string()

            if not text.contains(".") and not text.lower().contains("e"): text = "{text}.0"

            return write(writer: writer, text: text)
        BoolValue(boolean):
            if boolean: return write(writer: writer, text: "true")

            return write(writer: writer, text: "false")
        DateTimeValue(text):
            if not datetime_valid(text): return error(
                TomlError.InvalidData(
                    line: 0,
                    column: 0,
                    reason: "invalid TOML date or time text"
                )
            )

            return write(writer: writer, text: text)
        ArrayValue(values):
            for active in writer.active_arrays:
                if same_list(left: values, right: active): return error(
                    TomlError.InvalidData(
                        line: 0,
                        column: 0,
                        reason: "cyclic TOML value"
                    )
                )

            writer.active_arrays.append(values)
            let opening = try write(writer: writer, text: "[")
            var first = true

            for item in values:
                if not first: let separator = try write(writer: writer, text: ", ")

                first = false
                let written = try write_value(
                    writer: writer,
                    value: item,
                    depth: (depth + 1)
                )

            writer.active_arrays.remove(writer.active_arrays.length() - 1)
            return write(writer: writer, text: "]")
        TableValue(values):
            for active in writer.active_tables:
                if same_table(left: values, right: active): return error(
                    TomlError.InvalidData(
                        line: 0,
                        column: 0,
                        reason: "cyclic TOML value"
                    )
                )

            writer.active_tables.append(values)
            let opening = try write(writer: writer, text: "\{")
            var first = true

            for entry in values:
                if not first: let separator = try write(writer: writer, text: ", ")

                first = false
                let key = try write_quoted(writer: writer, text: entry.key)
                let equals = try write(writer: writer, text: " = ")
                let written = try write_value(
                    writer: writer,
                    value: entry.value,
                    depth: (depth + 1)
                )

            writer.active_tables.remove(writer.active_tables.length() - 1)
            return write(writer: writer, text: "\}")

# Serializes a TOML table document with quoted keys, inline nested tables and ordered arrays.
# Non-table roots, invalid date/time text and cycles return InvalidData with line/column zero.
# Float kinds, signed zero and nonfinite values are preserved; date/time tokens retain their text.
# Supplied limits bound UTF-8 output bytes, root-one value depth and value count; none adds no budget.
export fn stringify(
    value: TomlValue,
    limits: Optional[TomlLimits] = none
) -> Result[String, TomlError]:
    var options = TomlLimits(max_bytes: none, max_depth: none, max_values: none)

    match limits:
        none: let ignored = unit
        some(value): options = value

    for limit in [options.max_bytes, options.max_depth, options.max_values]:
        match limit:
            none: let ignored = unit
            some(value):
                if value < 0: return error(TomlError.InvalidInput)

    let entries = match value:
        TableValue(entries): entries
        _: return error(
            TomlError.InvalidData(
                line: 0,
                column: 0,
                reason: "TOML document root must be a table"
            )
        )

    let writer = Writer(
        parts: [],
        bytes: 0,
        values: 0,
        limits: options,
        active_arrays: [],
        active_tables: []
    )
    let counted = try write_count(writer: writer, depth: 1)
    writer.active_tables.append(entries)

    for entry in entries:
        let key = try write_quoted(writer: writer, text: entry.key)
        let equals = try write(writer: writer, text: " = ")
        let written = try write_value(writer: writer, value: entry.value, depth: 2)
        let newline = try write(writer: writer, text: "\n")

    return ok(writer.parts.join(separator: ""))
