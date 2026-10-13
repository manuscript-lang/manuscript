# TOML 1.0 parser implemented in Manuscript.
import {List, Map} from "@std/collections.ms"
import {parse_int, parse_float} from "@std/numbers.ms"
import from_scalars from "@std/string.ms"
import {log, sqrt} from "@std/math.ms"

# A TOML value. Date and time values retain their original TOML text.
export type TomlValue:
    case StringValue(value: String)
    case IntValue(value: Int)
    case FloatValue(value: Float)
    case BoolValue(value: Bool)
    case DateTimeValue(text: String)
    case ArrayValue(values: List[TomlValue])
    case TableValue(values: Map[String, TomlValue])

# Errors returned for invalid limits, malformed TOML, or exceeded resource bounds.
export type TomlError:
    case InvalidInput
    case InvalidData(line: Int, column: Int, reason: String)
    case LimitExceeded

# Optional input-byte, nesting-depth, and parsed-value limits for TOML parsing.
export type TomlLimits:
    max_bytes: Optional[Int]
    max_depth: Optional[Int]
    max_values: Optional[Int]

impl Error for TomlError:
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

            match parse_int(text: hex, radix: 16):
                error(_): return error(
                    invalid(
                        reader: reader,
                        reason: "invalid Unicode escape"
                    )
                )

                ok(scalar):
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

    match parent.entries.get(key):
        none:
            let allocated = try allocate(reader)
            let created = table(explicit: false, dotted: dotted)
            parent.entries.with_entry(
                key: key,
                value: Node.TableNode(created)
            )
            return ok(created)

        some(node):
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

    current.entries.with_entry(key: key, value: value)
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

    let year = text.slice(start: 0, end: 4)
    let month = text.slice(start: 5, end: 7)
    let day = text.slice(start: 8, end: 10)
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
        text: text.slice(start: 0, end: 2),
        minimum: 0,
        maximum: 23
    ): return false
    if not date_number(
        text: text.slice(start: 3, end: 5),
        minimum: 0,
        maximum: 59
    ): return false
    if not date_number(
        text: text.slice(start: 6, end: 8),
        minimum: 0,
        maximum: 60
    ): return false
    if text.scalar_length() == 8: return true

    let fraction = text.slice(
        start: 9,
        end: text.scalar_length()
    )
    return (
        text.at(8).unwrap_or("") == "."
        and decimal_digits(fraction)
        and not fraction.contains("_")
    )

fn datetime_valid(text: String) -> Bool:
    if date_valid(text): return true
    if time_valid(text): return true
    if text.scalar_length() < 19 or not date_valid(text.slice(start: 0, end: 10)): return false

    let separator = text.at(10).unwrap_or("")
    if (
        separator != "T"
        and separator != "t"
        and separator != " "
    ): return false

    var rest = text.slice(
        start: 11,
        end: text.scalar_length()
    )

    if rest.ends_with("Z") or rest.ends_with("z"):
        rest = rest.slice(start: 0, end: rest.scalar_length() - 1)
    else if rest.contains("+") or rest.contains("-"):
        var index = rest.index_of("+").unwrap_or(-1)

        if index < 0: index = rest.index_of("-").unwrap_or(-1)

        let zone = rest.slice(
            start: index + 1,
            end: rest.scalar_length()
        )
        if zone.scalar_length() != 5 or zone.at(2).unwrap_or("") != ":": return false
        if not date_number(
            text: zone.slice(start: 0, end: 2),
            minimum: 0,
            maximum: 23
        ): return false
        if not date_number(
            text: zone.slice(start: 3, end: 5),
            minimum: 0,
            maximum: 59
        ): return false

        rest = rest.slice(start: 0, end: index)

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
        )

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
                ),
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

                if exponent.starts_with("+") or exponent.starts_with("-"): exponent = exponent.slice(
                    start: 1,
                    end: exponent.scalar_length()
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

    return scalar(reader: reader, text: text)

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
                entries.with_entry(
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

    # TOML permits CR only as part of CRLF.
    let normalized = text.replace(
        old: "\r\n",
        new: "\n",
        max_replacements: text.byte_length()
    )
    if normalized.contains("\r"): return error(
        TomlError.InvalidData(
            line: 1,
            column: 1,
            reason: "bare carriage return"
        )
    )

    for code in normalized.scalar_values():
        if (
            code < 32
            and code != 9
            and code != 10
        ) or code == 127: return error(
            TomlError.InvalidData(
                line: 1,
                column: 1,
                reason: "invalid control character"
            )
        )

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

                match parent.entries.get(key):
                    none:
                        let allocated_array = try allocate(reader)
                        (
                            parent.entries.with_entry(
                                key: key,
                                value: Node.TableArray(
                                    [next]
                                )
                            )
                        )
                        unit

                    some(node):
                        match node:
                            TableArray(tables):
                                tables.append(next)
                                unit

                            _: return error(
                                invalid(
                                    reader: reader,
                                    reason: "table array conflicts with value"
                                )
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
