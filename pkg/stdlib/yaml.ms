# Configuration-oriented YAML 1.2 parser implemented in Manuscript.
import parse_int from "@std/numbers.ms"
import {from_scalars, StringBuilder} from "@std/string.ms"

# A YAML value represented as null, boolean, number text, string, array, or object.
export type YamlValue:
    # YAML null, including an empty document or a plain null spelling.
    case Null
    # A core-schema true or false value; yes and no remain strings.
    case BoolValue(
        # The decoded boolean selected from YAML core-schema spellings.
        value: Bool
    )
    # Numeric token text retained exactly instead of being coerced into Float.
    case NumberValue(
        # Original numeric spelling, including supported base prefixes and nonfinite spellings.
        text: String
    )
    # Text decoded from a quoted, plain or block scalar.
    case StringValue(
        # Resulting Unicode text after escape decoding, folding and chomping.
        value: String
    )
    # An ordered YAML sequence with ordinary mutable list storage.
    case ArrayValue(
        # Sequence entries in document order, retaining nested references.
        values: List[YamlValue]
    )
    # A textual-key mapping, with insertion order and duplicate-key checks.
    case ObjectValue(
        # Decoded string keys and their values; aliases may share nested payloads.
        values: Map[String, YamlValue]
    )

# Errors returned for malformed YAML, unsupported features, or exceeded resource limits.
export type YamlError:
    # A supplied limit is negative, or stringify received a number whose text is not a YAML number.
    case InvalidInput
    # Malformed YAML or a form outside the supported parser's accepted grammar.
    case InvalidData(
        # One-based source line of the offending token or construct.
        line: Int,
        # One-based Unicode scalar column within that source line.
        column: Int,
        # Parser diagnostic describing the malformed construct.
        reason: String
    )
    # An explicit tag, complex key or directive unsupported by this configuration parser.
    case UnsupportedFeature(
        # One-based source line where the unsupported construct appears.
        line: Int,
        # Diagnostic identifying the unsupported syntax or feature.
        reason: String
    )
    # Parsing or validating the returned alias-expanded tree exceeds a supplied budget.
    case LimitExceeded

# Optional input-byte, nesting-depth, and parsed-value limits for YAML parsing.
export type YamlLimits:
    # Maximum UTF-8 input bytes before line-ending normalization; none adds no budget.
    max_bytes: Optional[Int] = none
    # Maximum value depth, including scalar leaves, with the root at one.
    max_depth: Optional[Int] = none
    # Maximum containers and leaves, excluding keys; aliases count at each checked occurrence.
    max_values: Optional[Int] = none

impl Error for YamlError:
    # Formats parser positions and reason text; match the typed fields for programmatic handling.
    fn message() String:
        match self:
            InvalidInput: return "invalid YAML input"
            InvalidData(line, column, reason): return "YAML {line}:{column}: {reason}"
            UnsupportedFeature(line, reason): return "YAML {line}: {reason}"
            LimitExceeded: return "YAML limit exceeded"

type Context:
    lines: List[String]
    final_break: Bool
    index: Int
    limits: YamlLimits
    values: Int
    anchors: Map[String, YamlValue]

type Flow:
    chars: List[String]
    pos: Int
    line: Int
    context: Context
    delimited: Bool

fn within(value: Int, limit: Optional[Int]) Bool:
    if let maximum = limit:
        return value <= maximum

    return true

fn count(context: Context, depth: Int) Result[Unit, YamlError]:
    if not within(depth, context.limits.max_depth): return error(
        YamlError.LimitExceeded
    )

    context.values += 1
    if not within(context.values, context.limits.max_values): return error(
        YamlError.LimitExceeded
    )

    return ok(unit)

fn invalid(context: Context, reason: String) YamlError:
    return YamlError.InvalidData(line: context.index + 1, column: 1, reason: reason)

fn peek(flow: Flow) String:
    return flow.chars.at(flow.pos).get("")

fn advance(flow: Flow) String:
    let c = peek(flow)
    if c != "": flow.pos += 1
    return c

fn flow_space(flow: Flow) Unit:
    while (peek(flow) == " " or peek(flow) == "\t" or peek(flow) == "\n"): advance(flow)

fn flow_invalid(flow: Flow, reason: String) YamlError:
    return YamlError.InvalidData(line: flow.line, column: flow.pos + 1, reason: reason)

# The first physical break folds to a space, or is removed before empty lines.
# An escaped first break is removed even when no empty lines follow it.
fn folded_break(flow: Flow, escaped: Bool) String:
    var result = ""

    while true:
        while peek(flow) == " " or peek(flow) == "\t": advance(flow)
        if peek(flow) != "\n": break

        advance(flow)
        result = result.concat("\n")

    if result == "" and not escaped: return " "

    return result

fn quoted(flow: Flow) Result[String, YamlError]:
    let quote = advance(flow)
    # Append through a builder: per-character concatenation is quadratic on long strings.
    let result = StringBuilder()
    var whitespace = StringBuilder()

    while true:
        let c = advance(flow)
        if c == "": return error(flow_invalid(flow, "unterminated string"))

        if c == quote:
            result.append(whitespace.freeze())
            whitespace = StringBuilder()

            if quote == "'" and peek(flow) == "'":
                advance(flow)
                result.append("'")
                continue

            return ok(result.freeze())

        if c == "\n":
            whitespace = StringBuilder()
            result.append(folded_break(flow, escaped: false))
            continue

        if c == " " or c == "\t":
            whitespace.append(c)
            continue

        result.append(whitespace.freeze())
        whitespace = StringBuilder()

        if c != "\\" or quote == "'":
            result.append(c)
            continue

        let escaped = advance(flow)

        if escaped == "\n":
            result.append(folded_break(flow, escaped: true))
        else if escaped == "0": result.append("\u{0}")
        else if escaped == "a": result.append("\u{7}")
        else if escaped == "b": result.append("\u{8}")
        else if escaped == "t" or escaped == "\t": result.append("\t")
        else if escaped == "n": result.append("\n")
        else if escaped == "v": result.append("\u{b}")
        else if escaped == "f": result.append("\u{c}")
        else if escaped == "r": result.append("\r")
        else if escaped == "e": result.append("\u{1b}")
        else if (escaped == " " or escaped == "\"" or escaped == "/" or escaped == "\\"): result.append(
            escaped
        )
        else if escaped == "N": result.append("\u{85}")
        else if escaped == "_": result.append("\u{a0}")
        else if escaped == "L": result.append("\u{2028}")
        else if escaped == "P": result.append("\u{2029}")
        else if (escaped == "x" or escaped == "u" or escaped == "U"):
            var count = 2
            if escaped == "u": count = 4
            if escaped == "U": count = 8
            var hex = ""

            while count > 0:
                let digit = advance(flow)
                if digit == "" or not "0123456789abcdefABCDEF".contains(digit): return error(
                    flow_invalid(flow, "invalid Unicode escape")
                )

                hex = hex.concat(digit)
                count -= 1

            let parsed = parse_int(hex, 16)
            if parsed.is_error(): return error(
                flow_invalid(flow, "invalid Unicode escape")
            )

            if let text = from_scalars([parsed.get()]):
                result.append(text)
            else:
                return error(flow_invalid(flow, "invalid Unicode scalar"))
        else:
            return error(flow_invalid(flow, "invalid string escape"))

fn digit_text(text: String) Bool:
    if text == "": return false

    for c in text.split(""):
        if not "0123456789".contains(c): return false
    return true

fn numeric(text: String) Bool:
    var clean = text
    if clean.starts_with("+") or clean.starts_with("-"): clean = (
        clean
        .slice(1, clean.scalar_length())
        .get("")
    )
    if (clean == ".inf" or clean == ".Inf" or clean == ".INF"): return true
    if (text == ".nan" or text == ".NaN" or text == ".NAN"): return true

    if clean.starts_with("0x") or clean.starts_with("0o"):
        if clean != text: return false

        var alphabet = "01234567"
        if clean.starts_with("0x"): alphabet = "0123456789abcdefABCDEF"
        let digits = clean.slice(2, clean.scalar_length()).get("")
        if digits == "": return false

        for c in digits.split(""):
            if not alphabet.contains(c): return false
        return true

    let exponent = clean.lower().split("e")
    if exponent.length() > 2: return false

    if exponent.length() == 2:
        var power = exponent.last().get()
        if power.starts_with("+") or power.starts_with("-"): power = (
            power
            .slice(1, power.scalar_length())
            .get("")
        )
        if not digit_text(power): return false

    let mantissa = exponent.first().get().split(".")
    if mantissa.length() > 2: return false
    if mantissa.length() == 1: return digit_text(mantissa.first().get())

    let whole = mantissa.first().get()
    let fraction = mantissa.last().get()
    if whole == "" and fraction == "": return false

    return (
        (whole == "" or digit_text(whole))
        and (fraction == "" or digit_text(fraction))
    )

fn plain(text: String) YamlValue:
    if (text == "" or text == "~" or text == "null" or text == "Null" or text == "NULL"): return YamlValue.Null
    if (text == "true" or text == "True" or text == "TRUE"): return YamlValue.BoolValue(
        true
    )
    if (text == "false" or text == "False" or text == "FALSE"): return YamlValue.BoolValue(
        false
    )
    if numeric(text): return YamlValue.NumberValue(text)

    return YamlValue.StringValue(text)

fn anchor_name(flow: Flow) Result[String, YamlError]:
    var name = ""
    while peek(flow) != "" and not " \t\n,[]\{\}".contains(peek(flow)):
        name = name.concat(advance(flow))
    if name == "": return error(flow_invalid(flow, "empty anchor name"))

    return ok(name)

fn merge(
    line: Int,
    column: Int,
    target: Map[String, YamlValue],
    value: YamlValue
) Result[Unit, YamlError]:
    let values = match value:
        ObjectValue(entries):
            for entry in entries:
                if not target.contains(entry.key): target.add(entry.key, entry.value)
            return ok(unit)
        ArrayValue(values): values
        _: return error(
            YamlError.InvalidData(
                line: line,
                column: column,
                reason: "merge requires mappings"
            )
        )

    for item in values:
        match item:
            ObjectValue(_): try merge(
                line: line,
                column: column,
                target: target,
                value: item
            )
            _: return error(
                YamlError.InvalidData(
                    line: line,
                    column: column,
                    reason: "merge requires mappings"
                )
            )

    return ok(unit)

# A plain scalar continued across lines folds each break into one space; blank lines stay breaks.
fn fold_plain(text: String) String:
    if not text.contains("\n"): return text

    var result = ""
    var blanks = 0
    var first = true

    for line in text.split("\n"):
        let trimmed = line.trim()

        if trimmed == "":
            blanks += 1
            continue

        if first: result = trimmed
        else if blanks == 0: result = result.concat(" ").concat(trimmed)
        else:
            var breaks = ""
            var remaining = blanks

            while remaining > 0:
                breaks = breaks.concat("\n")
                remaining -= 1

            result = result.concat(breaks).concat(trimmed)

        blanks = 0
        first = false

    return result

fn flow_value(flow: Flow, depth: Int, key: Bool) Result[YamlValue, YamlError]:
    flow_space(flow)
    if not key:
        try count(flow.context, depth)
    let c = peek(flow)

    if c == "&":
        advance(flow)
        let name = try anchor_name(flow)
        flow.context.values -= 1
        let value = try flow_value(flow, depth, key: false)
        flow.context.anchors.add(name, value)
        return ok(value)

    if c == "*":
        advance(flow)
        if let value = try anchor_name(flow) | flow.context.anchors.get:
            return ok(value)

        return error(flow_invalid(flow, "unknown or recursive alias"))

    if c == "!": return error(
        YamlError.UnsupportedFeature(
            line: flow.line,
            reason: "explicit tags are unsupported"
        )
    )
    if c == "\"" or c == "'": return ok(YamlValue.StringValue(try quoted(flow)))

    if c == "[":
        flow.delimited = true
        if key: return error(
            YamlError.UnsupportedFeature(
                line: flow.line,
                reason: "complex mapping keys are unsupported"
            )
        )

        advance(flow)
        let values: List[YamlValue] = []
        flow_space(flow)

        while peek(flow) != "]":
            if peek(flow) == "" or peek(flow) == ",": return error(
                flow_invalid(flow, "expected flow sequence value")
            )

            values.append(try flow_value(flow, depth + 1, key: false))
            flow_space(flow)
            if peek(flow) == "]": break
            if advance(flow) != ",": return error(
                flow_invalid(flow, "expected sequence comma")
            )

            flow_space(flow)

        advance(flow)
        return ok(YamlValue.ArrayValue(values))

    if c == "\{":
        flow.delimited = true
        if key: return error(
            YamlError.UnsupportedFeature(
                line: flow.line,
                reason: "complex mapping keys are unsupported"
            )
        )

        advance(flow)
        let values = Map[String, YamlValue]()
        let explicit = Set[String]()
        flow_space(flow)

        while peek(flow) != "\}":
            if peek(flow) == "": return error(
                flow_invalid(flow, "unterminated flow mapping")
            )

            let quoted_key = peek(flow) == "\"" or peek(flow) == "'"
            let parsed_key = try flow_value(flow, depth, key: true)
            var name = ""

            match parsed_key:
                StringValue(value): name = value
                _: return error(
                    YamlError.UnsupportedFeature(
                        line: flow.line,
                        reason: "mapping keys must be strings"
                    )
                )

            flow_space(flow)
            var value = YamlValue.Null

            # A key with no colon, as in `{a, b: 1}`, maps to null.
            if peek(flow) == "," or peek(flow) == "\}":
                try count(flow.context, depth + 1)
            else:
                if advance(flow) != ":": return error(
                    flow_invalid(flow, "expected mapping colon")
                )

                value = try flow_value(flow, depth + 1, key: false)

            if explicit.contains(name): return error(
                flow_invalid(flow, "duplicate mapping key")
            )

            explicit.add(name)

            if name == "<<" and not quoted_key:
                try merge(
                    line: flow.line,
                    column: flow.pos + 1,
                    target: values,
                    value: value
                )
            else:
                values.add(name, value)

            flow_space(flow)
            if peek(flow) == "\}": break
            if advance(flow) != ",": return error(
                flow_invalid(flow, "expected mapping comma")
            )

            flow_space(flow)

        advance(flow)
        return ok(YamlValue.ObjectValue(values))

    let start = flow.pos

    while (
        peek(flow) != ""
        and not ((flow.delimited or key) and ",[]\{\}".contains(peek(flow)))
        and not (key and peek(flow) == ":")
    ):
        if peek(flow) == ":" and flow.chars.at(flow.pos + 1).get("") == " ": return error(
            flow_invalid(flow, "unexpected mapping colon")
        )

        advance(flow)

    # Slice once: appending each character to a string is quadratic on long scalars.
    var text = (flow.chars.slice(start, flow.pos).get([]).join("").trim())
    if flow.delimited: text = fold_plain(text)
    if key: return ok(YamlValue.StringValue(text))

    return ok(plain(text))

fn quoted_or_nested(text: String) Bool:
    return (
        text.contains("\"")
        or text.contains("'")
        or text.contains("[")
        or text.contains("\{")
    )

# boundary for text with no quotes or brackets: the first marker that follows a blank (or ends the text) wins.
fn plain_boundary(text: String, colon: Bool) Int:
    var marker = "#"
    if colon: marker = ":"
    var offset = 0

    while true:
        let rest = (text.slice_scalars(offset, text.scalar_length()).get(""))
        let found = rest.index_of(marker).get(-1)
        if found < 0: return -1

        let at = offset + found
        let before = text.at(at - 1).get("")
        let after = text.at(at + 1).get("")
        if colon and (after == "" or after == " " or after == "\t"): return at
        if not colon and (at == 0 or before == " " or before == "\t"): return at

        offset = at + 1

# Find a mapping colon or comment outside quoted/flow values.
fn boundary(text: String, colon: Bool) Int:
    # Without the marker nothing can match; without quotes or brackets the first candidate decides.
    if colon and not text.contains(":"): return -1
    if not colon and not text.contains("#"): return -1
    if not quoted_or_nested(text): return plain_boundary(text, colon)

    let chars = text.split("")
    var quote = ""
    var depth = 0
    var index = 0

    while index < chars.length():
        let c = chars.at(index).get()

        if quote != "":
            if c == "\\" and quote == "\"": index += 1
            else if c == quote:
                if quote == "'" and chars.at(index + 1).get("") == "'": index = (
                    index
                    + 1
                )
                else: quote = ""
        else if (
            (c == "\"" or c == "'")
            and (
                index == 0
                or " \t\n:[\{,".contains((chars.at((index - 1)).get()))
            )
        ): quote = c
        else if c == "[" or c == "\{": depth += 1
        else if c == "]" or c == "\}": depth -= 1
        else if (
            colon
            and c == ":"
            and depth == 0
            and (
                index + 1 == chars.length()
                or chars.at((index + 1)).get("") == " "
                or chars.at((index + 1)).get("") == "\t"
            )
        ):
            return index
        else if (
            not colon
            and c == "#"
            and (
                index == 0
                or chars.at(index - 1).get("") == " "
                or chars.at((index - 1)).get("") == "\t"
            )
        ):
            return index

        index += 1

    return -1

fn uncomment(text: String) String:
    let index = boundary(text, colon: false)

    if index < 0:
        if not complete(text): return text

        return text.trim_end()

    return text.slice(0, index).get("").trim_end()

fn indent(text: String) Int:
    var result = 0
    while text.at(result).get("") == " ": result += 1
    return result

fn indentation(context: Context, text: String) Result[Int, YamlError]:
    let spaces = indent(text)
    if text.at(spaces).get("") == "\t": return error(
        invalid(context, "tabs cannot indent YAML")
    )

    return ok(spaces)

fn skip(context: Context) Unit:
    while (
        context.index < context.lines.length()
        and uncomment((context.lines.at(context.index).get())).trim() == ""
    ): context.index = (context.index + 1)

fn sequence(text: String) Bool:
    return (text == "-" or text.starts_with("- ") or text.starts_with("-\t"))

# A flow collection or quoted scalar can continue across physical lines.
fn complete(text: String) Bool:
    if not quoted_or_nested(text): return true

    var quote = ""
    var depth = 0
    var index = 0
    let chars = text.split("")

    while index < chars.length():
        let c = chars.at(index).get()

        if quote != "":
            if c == "\\" and quote == "\"": index += 1
            else if c == quote:
                if quote == "'" and chars.at(index + 1).get("") == "'": index = (
                    index
                    + 1
                )
                else: quote = ""
        else if (
            (c == "\"" or c == "'")
            and (
                index == 0
                or " \t\n:[\{,".contains((chars.at((index - 1)).get()))
            )
        ): quote = c
        else if c == "[" or c == "\{": depth += 1
        else if c == "]" or c == "\}": depth -= 1

        index += 1

    return quote == "" and depth <= 0

fn inline_value(context: Context, text: String, depth: Int) Result[YamlValue, YamlError]:
    var joined = text
    let line = context.index
    let structured = (
        text.starts_with("[")
        or text.starts_with("\{")
        or text.starts_with("\"")
        or text.starts_with("'")
        or text.starts_with("&")
    )

    while (
        structured
        and not complete(joined)
        and context.index < context.lines.length()
    ):
        let next = context.lines.at(context.index).get()
        # Keep quote state and physical empty lines when removing comments.
        let combined = joined.concat("\n").concat(next)
        let comment = boundary(combined, colon: false)

        if comment < 0: joined = combined
        else: joined = combined.slice(0, comment).get("")

        context.index += 1

    let flow = Flow(
        chars: joined.split(""),
        pos: 0,
        line: line,
        context: context,
        delimited: false
    )
    let result = try flow_value(flow, depth, key: false)
    flow_space(flow)
    if peek(flow) != "": return error(flow_invalid(flow, "unexpected trailing text"))

    return ok(result)

fn block_string(
    context: Context,
    header: String,
    base: Int
) Result[YamlValue, YamlError]:
    var mode = ""
    var explicit = 0
    var offset = 0
    # The header line was already consumed, so it is the previous line.
    let header_line = context.index
    let header_column = (
        context.lines.at(context.index - 1).get("").index_of(header).get(0)
        + 1
    )

    for c in (header.slice(1, header.scalar_length()).get("").split("")):
        offset += 1

        if (c == "+" or c == "-") and mode == "": mode = c
        else if "123456789".contains(c) and explicit == 0: explicit = (
            c
            .parse_int()
            .get()
        )
        else: return error(
            YamlError.InvalidData(
                line: header_line,
                column: header_column + offset,
                reason: "invalid block scalar header"
            )
        )

    var content_indent = base + explicit
    var probe = context.index

    if explicit == 0:
        var blank_indent = base + 1

        while (
            probe < context.lines.length()
            and context.lines.at(probe).get().slice(
                indent(context.lines.at(probe).get()),
                context.lines.at(probe).get().scalar_length()
            ).get("") == ""
        ):
            let spaces = indent(context.lines.at(probe).get())
            if spaces > blank_indent: blank_indent = spaces
            probe += 1

        if probe < context.lines.length(): content_indent = indent(
            (context.lines.at(probe).get())
        )
        if content_indent <= base: content_indent = blank_indent

    let parts: List[String] = []

    while context.index < context.lines.length():
        let line = context.lines.at(context.index).get()
        let spaces = indent(line)
        if (
            line.slice(spaces, line.scalar_length()).get("") != ""
            and spaces < content_indent
        ):
            break

        parts.append(line.slice(content_indent, line.scalar_length()).get(""))
        context.index += 1

    let builder = StringBuilder()
    var index = 0
    var content = false

    while index < parts.length():
        let part = parts.at(index).get()
        if part != "": content = true
        builder.append(part)
        var separator = "\n"

        if (
            header.starts_with(">")
            and part != ""
            and not part.starts_with(" ")
            and not part.starts_with("\t")
            and index + 1 < parts.length()
        ):
            var next_index = index + 1
            while next_index < parts.length() and parts.at(next_index).get() == "":
                next_index += 1

            if next_index < parts.length():
                let next = parts.at(next_index).get()

                if not next.starts_with(" ") and not next.starts_with("\t"):
                    if next_index == index + 1: separator = " "
                    else: separator = ""

        if (
            index + 1 == parts.length()
            and context.index == context.lines.length()
            and not context.final_break
        ): separator = ""
        builder.append(separator)
        index += 1

    var result = builder.freeze()

    if mode != "+":
        let final_break = result.ends_with("\n")
        # Count the final run of line feeds once: trimming one scalar at a time is quadratic.
        let pieces = result.split("\n")
        var trailing = 0
        while (trailing < pieces.length() and pieces.at(-1 - trailing).get("x") == ""): trailing += 1
        if trailing == pieces.length(): trailing -= 1
        result = (result.slice(0, (result.scalar_length() - trailing)).get(""))
        if (mode != "-" and content and final_break): result = result.concat("\n")

    return ok(YamlValue.StringValue(result))

fn block_value(
    context: Context,
    text: String,
    base: Int,
    depth: Int,
    indentless: Bool
) Result[YamlValue, YamlError]:
    var remainder = text.trim_start()
    var anchor = ""

    if remainder.starts_with("&"):
        let flow = Flow(
            chars: remainder.split(""),
            pos: 1,
            line: context.index,
            context: context,
            delimited: false
        )
        anchor = try anchor_name(flow)
        remainder = (
            remainder
            .slice(flow.pos, remainder.scalar_length())
            .get("")
            .trim_start()
        )

    var result = YamlValue.Null

    if remainder.starts_with("|") or remainder.starts_with(">"):
        try count(context, depth)
        result = try block_string(context, remainder.trim_end(), base)
    else if remainder != "":
        if not "['\"\{*&!".contains(remainder.at(0).get()):
            remainder = remainder.trim_end()
            let joined = StringBuilder()
            joined.append(remainder)
            var probe = context.index
            var blanks = 0

            while probe < context.lines.length():
                let line = context.lines.at(probe).get()

                if line.trim() == "":
                    blanks += 1
                    probe += 1
                    continue

                let next = uncomment(line)
                if next.trim() == "" or indent(next) <= base: break

                context.index = probe
                let _indent = try indentation(context, next)
                if (boundary(next, colon: true) >= 0 or sequence(next.trim_start())): return error(
                    invalid(
                        context,
                        "unexpected indented collection"
                    )
                )

                var separator = " "

                if blanks > 0:
                    separator = ""

                    while blanks > 0:
                        separator = separator.concat("\n")
                        blanks -= 1

                joined.append(separator)
                joined.append(next.trim())
                probe += 1
                context.index = probe

            remainder = joined.freeze()

        result = try inline_value(context, remainder, depth)
    else:
        skip(context)

        if context.index < context.lines.length():
            let line = uncomment(context.lines.at(context.index).get())
            let next_indent = try indentation(context, line)

            if (
                next_indent > base
                or (
                    indentless
                    and next_indent == base
                    and sequence(line.trim_start())
                )
            ):
                result = try block(context, next_indent, depth)
            else:
                try count(context, depth)
        else:
            try count(context, depth)

    if anchor != "": context.anchors.add(anchor, result)
    return ok(result)

fn pad(width: Int) String:
    let builder = StringBuilder()
    var spaces = width

    while spaces > 0:
        builder.append(" ")
        spaces -= 1

    return builder.freeze()

# Columns of the nested sequence levels opened by consecutive compact `- ` indicators.
fn nested_columns(line: String, base: Int) List[Int]:
    let chars = line.split("")
    let columns: List[Int] = []
    var marker = base

    while chars.at(marker).get("") == "-":
        var next = marker + 1
        while chars.at(next).get("") == " ": next += 1
        if next == marker + 1 or chars.at(next).get("") != "-": break

        let after = chars.at(next + 1).get("")
        if (after != "" and after != " " and after != "\t"): break

        columns.append(next)
        marker = next

    return columns

fn sequence_items(
    context: Context,
    values: List[YamlValue],
    base: Int,
    depth: Int
) Result[Unit, YamlError]:
    while context.index < context.lines.length():
        skip(context)
        if context.index >= context.lines.length(): break

        let line = uncomment(context.lines.at(context.index).get())
        let line_indent = try indentation(context, line)
        if line_indent < base: break
        if line_indent != base or not sequence(line.trim_start()): break

        let item = (
            line
            .trim_start()
            .slice(1, (line.trim_start().scalar_length()))
            .get("")
            .trim_start()
        )
        let chain = nested_columns(line, base)

        if chain.length() > 0:
            # A run of compact sequence indicators (`- - x`) opens one level per
            # indicator. Scan the line once and rewrite it once instead of per level.
            let innermost = chain.at(chain.length() - 1).get()
            let frames: List[List[YamlValue]] = []
            var level = 1

            while level <= chain.length():
                try count(context, (depth + level))
                frames.append([])
                level += 1

            (
                context
                .lines
                .set(
                    context.index,
                    pad(innermost).concat(
                        (
                            line
                            .slice(
                                innermost,
                                line.scalar_length()
                            )
                            .get("")
                        )
                    )
                )
            )
            level = chain.length()
            var nested = frames.at(level - 1).get()
            try sequence_items(
                context: context,
                values: nested,
                base: innermost,
                depth: (depth + level)
            )
            var value = YamlValue.ArrayValue(nested)
            level -= 1

            while level >= 1:
                nested = frames.at(level - 1).get()
                nested.append(value)
                try sequence_items(
                    context: context,
                    values: nested,
                    base: chain.at(level - 1).get(),
                    depth: (depth + level)
                )
                value = YamlValue.ArrayValue(nested)
                level -= 1

            values.append(value)
        else if sequence(item) or boundary(item, colon: true) >= 0:
            # Treat a compact mapping/sequence as a virtual indented first line.
            # Its column follows the indicator, so extra spaces move the nested base.
            let marker = (
                line
                .trim_start()
                .slice(1, (line.trim_start().scalar_length()))
                .get("")
            )
            var gap = indent(marker)
            if gap == 0: gap = 1
            let column = base + 1 + gap
            (context.lines.set(context.index, pad(column).concat(item)))
            values.append(try block(context, column, (depth + 1)))
        else:
            context.index += 1
            values.append(
                try block_value(
                    context: context,
                    text: item,
                    base: base,
                    depth: (depth + 1),
                    indentless: false
                )
            )

    return ok(unit)

fn block(context: Context, base: Int, depth: Int) Result[YamlValue, YamlError]:
    skip(context)
    let first = uncomment(context.lines.at(context.index).get()).trim_start()
    if first.starts_with("?"): return error(
        YamlError.UnsupportedFeature(
            line: (context.index + 1),
            reason: "explicit mapping keys are unsupported"
        )
    )

    if sequence(first):
        try count(context, depth)
        let values: List[YamlValue] = []
        try sequence_items(context: context, values: values, base: base, depth: depth)
        return ok(YamlValue.ArrayValue(values))

    if boundary(first, colon: true) >= 0:
        try count(context, depth)
        let values = Map[String, YamlValue]()
        let explicit = Set[String]()

        while context.index < context.lines.length():
            skip(context)
            if context.index >= context.lines.length(): break

            let line = uncomment(context.lines.at(context.index).get())
            let line_indent = try indentation(context, line)
            if line_indent != base or sequence(line.trim_start()): break

            let content = line.trim_start()
            let colon = boundary(content, colon: true)
            if colon < 0: break

            var name = content.slice(0, colon).get("").trim()
            let quoted_key = name.starts_with("\"") or name.starts_with("'")

            if quoted_key:
                let flow = Flow(
                    chars: name.split(""),
                    pos: 0,
                    line: (context.index + 1),
                    context: context,
                    delimited: false
                )
                name = try quoted(flow)
                if flow.pos != flow.chars.length(): return error(
                    invalid(context, "invalid quoted key")
                )
            else if (
                name == ""
                or name.starts_with("[")
                or name.starts_with("\{")
                or name.starts_with("!")
                or name.starts_with("&")
                or name.starts_with("*")
            ):
                return error(
                    YamlError.UnsupportedFeature(
                        line: context.index + 1,
                        reason: "mapping keys must be strings"
                    )
                )

            if explicit.contains(name): return error(
                invalid(context, "duplicate mapping key")
            )

            explicit.add(name)
            let text = (
                content
                .slice(colon + 1, content.scalar_length())
                .get("")
                .trim_start()
            )
            let key_line = context.index + 1
            context.index += 1
            let value = try block_value(
                context: context,
                text: text,
                base: base,
                depth: (depth + 1),
                indentless: true
            )

            if name == "<<" and not quoted_key:
                try merge(
                    line: key_line,
                    column: line_indent + 1,
                    target: values,
                    value: value
                )
            else:
                values.add(name, value)

        return ok(YamlValue.ObjectValue(values))

    context.index += 1
    return block_value(
        context: context,
        text: first,
        # A scalar or anchor on its own line may continue at the same indentation.
        base: base - 1,
        depth: depth,
        indentless: false
    )

fn validate(context: Context, value: YamlValue, depth: Int) Result[Unit, YamlError]:
    try count(context, depth)

    match value:
        ArrayValue(values):
            for item in values: try validate(context, item, (depth + 1))
        ObjectValue(values):
            for entry in values: try validate(context, entry.value, (depth + 1))
        _: unit

    return ok(unit)

# Parses a YAML document. Unsupported YAML features and invalid input include source locations.
export fn parse(
    text: String,
    limits: Optional[YamlLimits] = none
) Result[YamlValue, YamlError]:
    var options = YamlLimits()
    if let value = limits:
        options = value
    for limit in [options.max_bytes, options.max_depth, options.max_values]:
        if let value = limit:
            if value < 0: return error(YamlError.InvalidInput)
    if not within(text.byte_length(), options.max_bytes): return error(
        YamlError.LimitExceeded
    )

    var normalized = (
        text
        .replace("\r\n", "\n", text.byte_length())
        .replace("\r", "\n", text.byte_length())
    )
    if normalized.starts_with("\u{feff}"): normalized = (
        normalized
        .slice(1, normalized.scalar_length())
        .get("")
    )
    for code in normalized.scalar_values():
        if (
            (code < 32 and code != 9 and code != 10)
            or (code >= 127 and code <= 159 and code != 133)
        ):
            return error(
                YamlError.InvalidData(
                    line: 1,
                    column: 1,
                    reason: "invalid control character"
                )
            )
    let context = Context(
        lines: normalized.split("\n"),
        final_break: normalized.ends_with("\n"),
        index: 0,
        limits: options,
        values: 0,
        anchors: Map[String, YamlValue]()
    )
    # split's synthetic terminal empty line is not scalar content.
    if normalized.ends_with("\n"): context.lines.remove(context.lines.length() - 1)
    skip(context)

    if (
        context.index < context.lines.length()
        and context.lines.at(context.index).get().starts_with("%")
    ):
        if uncomment(context.lines.at(context.index).get()) != "%YAML 1.2": return error(
            YamlError.UnsupportedFeature(
                line: (context.index + 1),
                reason: "only the YAML 1.2 directive is supported"
            )
        )

        context.index += 1
        skip(context)
        if (
            context.index >= context.lines.length()
            or uncomment((context.lines.at(context.index).get())) != "---"
        ): return error(invalid(context, "directive requires document start"))

    # Content after the marker on the same line starts the document body.
    if (
        context.index < context.lines.length()
        and context.lines.at(context.index).get().starts_with("--- ")
    ):
        let line = context.lines.at(context.index).get()
        let rest = line.slice(4, line.scalar_length()).get("")
        if not rest.trim().starts_with("#"): (
            context
            .lines
            .splice(context.index, 1, ["---", rest])
        )

    if (
        context.index < context.lines.length()
        and uncomment((context.lines.at(context.index).get())) == "---"
    ):
        context.index += 1
        skip(context)

    var result = YamlValue.Null
    if (
        context.index < context.lines.length()
        and uncomment((context.lines.at(context.index).get())) != "..."
    ):
        result = try block(
            context,
            try indentation(
                context,
                (context.lines.at(context.index).get())
            ),
            1
        )
    skip(context)

    if (
        context.index < context.lines.length()
        and uncomment((context.lines.at(context.index).get())) == "..."
    ):
        context.index += 1
        skip(context)

    if context.index != context.lines.length(): return error(
        invalid(context, "unexpected indentation or additional document")
    )
    if options.max_depth.is_none() and options.max_values.is_none(): return ok(result)

    context.values = 0
    try validate(context, result, 1)
    return ok(result)

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
        else if code < 32 or (code >= 127 and code <= 159):
            result.append("\\u")
            result.append(hex4(code))
        else: result.append(c)

    result.append("\"")
    return result.freeze()

fn format_key(key: String) String:
    var plain = key != ""
    for c in key.chars():
        if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(
            c
        ): plain = false
    if plain and "0123456789-".contains(key.chars().first().get()): plain = false
    if (
        plain
        and [
            "null", "true", "false", "yes", "no", "on", "off", "y", "n"
        ].contains(key.lower())
    ): plain = false
    if plain: return key

    return quote_text(key)

# A number keeps its original token, so it must resolve back to a number.
fn valid_number(text: String) Bool:
    if let parsed = parse(text): return parsed == YamlValue.NumberValue(text)

    return false

fn scalar_text(value: YamlValue) Result[String, YamlError]:
    match value:
        Null: return ok("null")
        BoolValue(flag): return ok(flag.to_string())
        StringValue(text): return ok(quote_text(text))
        NumberValue(text):
            if not valid_number(text): return error(YamlError.InvalidInput)

            return ok(text)
        ArrayValue(values):
            if values.is_empty(): return ok("[]")

            return ok("")
        ObjectValue(values):
            if values.is_empty(): return ok("\{\}")

            return ok("")

fn is_block(value: YamlValue) Bool:
    match value:
        ArrayValue(values): return not values.is_empty()
        ObjectValue(values): return not values.is_empty()
        _: return false

fn emit_block(
    out: StringBuilder,
    value: YamlValue,
    indent: String
) Result[Unit, YamlError]:
    match value:
        ArrayValue(values):
            for item in values:
                if is_block(item):
                    out.append(indent.concat("-\n"))
                    try emit_block(out, item, indent.concat("  "))
                else:
                    let text = try scalar_text(item)
                    out.append(indent.concat("- ").concat(text).concat("\n"))

            return ok(unit)
        ObjectValue(values):
            for entry in values.entries():
                let key = format_key(entry.key)

                if is_block(entry.value):
                    out.append(indent.concat(key).concat(":\n"))
                    try emit_block(out, entry.value, indent.concat("  "))
                else:
                    let text = try scalar_text(entry.value)
                    out.append(
                        indent.concat(key).concat(": ").concat(
                            text
                        ).concat("\n")
                    )

            return ok(unit)
        _: return ok(unit)

# Serializes a YAML value in block style with double-quoted strings.
export fn stringify(
    value: YamlValue,
    max_bytes: Optional[Int] = none
) Result[String, YamlError]:
    if let limit = max_bytes:
        if limit < 0: return error(YamlError.InvalidInput)
    let out = StringBuilder()

    if is_block(value): try emit_block(out, value, "")
    else:
        let text = try scalar_text(value)
        out.append(text.concat("\n"))

    let text = out.freeze()
    if not within(text.byte_length(), max_bytes): return error(YamlError.LimitExceeded)

    return ok(text)
