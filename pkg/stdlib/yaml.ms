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
    fn message() -> String:
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

fn within(value: Int, limit: Optional[Int]) -> Bool:
    match limit:
        none: return true
        some(maximum): return value <= maximum

fn count(context: Context, depth: Int) -> Result[Unit, YamlError]:
    if not within(value: depth, limit: context.limits.max_depth): return error(
        YamlError.LimitExceeded
    )

    context.values = context.values + 1
    if not within(value: context.values, limit: context.limits.max_values): return error(
        YamlError.LimitExceeded
    )

    return ok(unit)

fn invalid(context: Context, reason: String) -> YamlError:
    return YamlError.InvalidData(line: context.index + 1, column: 1, reason: reason)

fn peek(flow: Flow) -> String:
    return flow.chars.at(flow.pos).unwrap_or("")

fn advance(flow: Flow) -> String:
    let c = peek(flow)

    if c != "": flow.pos = flow.pos + 1

    return c

fn flow_space(flow: Flow) -> Unit:
    while (peek(flow) == " " or peek(flow) == "\t" or peek(flow) == "\n"): advance(flow)

fn flow_invalid(flow: Flow, reason: String) -> YamlError:
    return YamlError.InvalidData(line: flow.line, column: flow.pos + 1, reason: reason)

# The first physical break folds to a space, or is removed before empty lines.
# An escaped first break is removed even when no empty lines follow it.
fn folded_break(flow: Flow, escaped: Bool) -> String:
    var result = ""

    while true:
        while peek(flow) == " " or peek(flow) == "\t": advance(flow)

        if peek(flow) != "\n": break

        advance(flow)
        result = result.concat("\n")

    if result == "" and not escaped: return " "

    return result

fn quoted(flow: Flow) -> Result[String, YamlError]:
    let quote = advance(flow)
    # Append through a builder: per-character concatenation is quadratic on long strings.
    let result = StringBuilder()
    var whitespace = StringBuilder()

    while true:
        let c = advance(flow)
        if c == "": return error(
            flow_invalid(flow: flow, reason: "unterminated string")
        )

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
            result.append(folded_break(flow: flow, escaped: false))
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
            result.append(folded_break(flow: flow, escaped: true))
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
                    flow_invalid(
                        flow: flow,
                        reason: "invalid Unicode escape"
                    )
                )

                hex = hex.concat(digit)
                count = count - 1

            let value = match parse_int(text: hex, radix: 16):
                error(_): return error(
                    flow_invalid(
                        flow: flow,
                        reason: "invalid Unicode escape"
                    )
                )

                ok(value): value

            match from_scalars([value]):
                error(_): return error(
                    flow_invalid(
                        flow: flow,
                        reason: "invalid Unicode scalar"
                    )
                )
                ok(text): result.append(text)

        else:
            return error(flow_invalid(flow: flow, reason: "invalid string escape"))

fn digit_text(text: String) -> Bool:
    if text == "": return false

    for c in text.split(separator: ""):
        if not "0123456789".contains(c): return false

    return true

fn numeric(text: String) -> Bool:
    var clean = text

    if clean.starts_with("+") or clean.starts_with("-"): clean = (
        clean
        .slice(start: 1, end: clean.scalar_length)
        .unwrap_or("")
    )

    if (clean == ".inf" or clean == ".Inf" or clean == ".INF"): return true
    if (text == ".nan" or text == ".NaN" or text == ".NAN"): return true

    if clean.starts_with("0x") or clean.starts_with("0o"):
        if clean != text: return false

        var alphabet = "01234567"

        if clean.starts_with("0x"): alphabet = "0123456789abcdefABCDEF"

        let digits = clean.slice(start: 2, end: clean.scalar_length).unwrap_or("")
        if digits == "": return false

        for c in digits.split(separator: ""):
            if not alphabet.contains(c): return false

        return true

    let exponent = clean.lower().split(separator: "e")
    if exponent.length > 2: return false

    if exponent.length == 2:
        var power = exponent.last.unwrap()

        if power.starts_with("+") or power.starts_with("-"): power = (
            power
            .slice(start: 1, end: power.scalar_length)
            .unwrap_or("")
        )

        if not digit_text(power): return false

    let mantissa = exponent.first.unwrap().split(separator: ".")
    if mantissa.length > 2: return false
    if mantissa.length == 1: return digit_text(mantissa.first.unwrap())

    let whole = mantissa.first.unwrap()
    let fraction = mantissa.last.unwrap()
    if whole == "" and fraction == "": return false

    return (
        (whole == "" or digit_text(whole))
        and (fraction == "" or digit_text(fraction))
    )

fn plain(text: String) -> YamlValue:
    if (text == "" or text == "~" or text == "null" or text == "Null" or text == "NULL"): return YamlValue.Null
    if (text == "true" or text == "True" or text == "TRUE"): return YamlValue.BoolValue(
        true
    )
    if (text == "false" or text == "False" or text == "FALSE"): return YamlValue.BoolValue(
        false
    )
    if numeric(text): return YamlValue.NumberValue(text)

    return YamlValue.StringValue(text)

fn anchor_name(flow: Flow) -> Result[String, YamlError]:
    var name = ""

    while peek(flow) != "" and not " \t\n,[]\{\}".contains(peek(flow)):
        name = name.concat(advance(flow))

    if name == "": return error(flow_invalid(flow: flow, reason: "empty anchor name"))

    return ok(name)

fn merge(
    line: Int,
    column: Int,
    target: Map[String, YamlValue],
    value: YamlValue
) -> Result[Unit, YamlError]:
    let values = match value:
        ObjectValue(entries):
            for entry in entries:
                if not target.contains(entry.key): target.add(
                    key: entry.key,
                    value: entry.value
                )

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
            ObjectValue(_): let merged = try merge(
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
fn fold_plain(text: String) -> String:
    if not text.contains("\n"): return text

    var result = ""
    var blanks = 0
    var first = true

    for line in text.split(separator: "\n"):
        let trimmed = line.trim()

        if trimmed == "":
            blanks = blanks + 1
            continue

        if first: result = trimmed
        else if blanks == 0: result = result.concat(" ").concat(trimmed)
        else:
            var breaks = ""
            var remaining = blanks

            while remaining > 0:
                breaks = breaks.concat("\n")
                remaining = remaining - 1

            result = result.concat(breaks).concat(trimmed)

        blanks = 0
        first = false

    return result

fn flow_value(flow: Flow, depth: Int, key: Bool) -> Result[YamlValue, YamlError]:
    flow_space(flow)

    if not key:
        let counted = try count(context: flow.context, depth: depth)

    let c = peek(flow)

    if c == "&":
        advance(flow)
        let name = try anchor_name(flow)
        flow.context.values = flow.context.values - 1
        let value = try flow_value(flow: flow, depth: depth, key: false)
        flow.context.anchors.add(key: name, value: value)
        return ok(value)

    if c == "*":
        advance(flow)
        let name = try anchor_name(flow)

        match flow.context.anchors.get(name):
            some(value): return ok(value)
            none: return error(
                flow_invalid(
                    flow: flow,
                    reason: "unknown or recursive alias"
                )
            )

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
                flow_invalid(
                    flow: flow,
                    reason: "expected flow sequence value"
                )
            )

            values.append(try flow_value(flow: flow, depth: depth + 1, key: false))
            flow_space(flow)
            if peek(flow) == "]": break
            if advance(flow) != ",": return error(
                flow_invalid(
                    flow: flow,
                    reason: "expected sequence comma"
                )
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
                flow_invalid(
                    flow: flow,
                    reason: "unterminated flow mapping"
                )
            )

            let quoted_key = peek(flow) == "\"" or peek(flow) == "'"
            let parsed_key = try flow_value(flow: flow, depth: depth, key: true)
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
                let counted = try count(context: flow.context, depth: depth + 1)
            else:
                if advance(flow) != ":": return error(
                    flow_invalid(
                        flow: flow,
                        reason: "expected mapping colon"
                    )
                )

                value = try flow_value(flow: flow, depth: depth + 1, key: false)

            if explicit.contains(name): return error(
                flow_invalid(
                    flow: flow,
                    reason: "duplicate mapping key"
                )
            )

            explicit.add(name)

            if name == "<<" and not quoted_key:
                let merged = try merge(
                    line: flow.line,
                    column: flow.pos + 1,
                    target: values,
                    value: value
                )
            else:
                values.add(key: name, value: value)

            flow_space(flow)
            if peek(flow) == "\}": break
            if advance(flow) != ",": return error(
                flow_invalid(
                    flow: flow,
                    reason: "expected mapping comma"
                )
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
        if peek(flow) == ":" and flow.chars.at(flow.pos + 1).unwrap_or("") == " ": return error(
            flow_invalid(flow: flow, reason: "unexpected mapping colon")
        )

        advance(flow)

    # Slice once: appending each character to a string is quadratic on long scalars.
    var text = (
        flow
        .chars
        .slice(start: start, end: flow.pos)
        .unwrap_or([])
        .join("")
        .trim()
    )

    if flow.delimited: text = fold_plain(text)

    if key: return ok(YamlValue.StringValue(text))

    return ok(plain(text))

# Find a mapping colon or comment outside quoted/flow values.
fn boundary(text: String, colon: Bool) -> Int:
    let chars = text.split(separator: "")
    var quote = ""
    var depth = 0
    var index = 0

    while index < chars.length:
        let c = chars.at(index).unwrap()

        if quote != "":
            if c == "\\" and quote == "\"": index = index + 1
            else if c == quote:
                if quote == "'" and chars.at(index + 1).unwrap_or("") == "'": index = (
                    index
                    + 1
                )
                else: quote = ""
        else if (
            (c == "\"" or c == "'")
            and (
                index == 0
                or " \t\n:[\{,".contains(
                    (chars.at((index - 1)).unwrap())
                )
            )
        ): quote = c
        else if c == "[" or c == "\{": depth = depth + 1
        else if c == "]" or c == "\}": depth = depth - 1
        else if (
            colon
            and c == ":"
            and depth == 0
            and (
                index + 1 == chars.length
                or chars.at((index + 1)).unwrap_or("") == " "
                or chars.at((index + 1)).unwrap_or("") == "\t"
            )
        ):
            return index
        else if (
            not colon
            and c == "#"
            and (
                index == 0
                or chars.at(index - 1).unwrap_or("") == " "
                or chars.at((index - 1)).unwrap_or("") == "\t"
            )
        ):
            return index

        index = index + 1

    return -1

fn uncomment(text: String) -> String:
    let index = boundary(text: text, colon: false)

    if index < 0:
        if not complete(text): return text

        return text.trim_end()

    return text.slice(start: 0, end: index).unwrap_or("").trim_end()

fn indent(text: String) -> Int:
    var result = 0

    for c in text.split(separator: ""):
        if c != " ": break

        result = result + 1

    return result

fn indentation(context: Context, text: String) -> Result[Int, YamlError]:
    let spaces = indent(text)
    if text.at(spaces).unwrap_or("") == "\t": return error(
        invalid(context: context, reason: "tabs cannot indent YAML")
    )

    return ok(spaces)

fn skip(context: Context) -> Unit:
    while (
        context.index < context.lines.length
        and uncomment((context.lines.at(context.index).unwrap())).trim() == ""
    ): context.index = (context.index + 1)

fn sequence(text: String) -> Bool:
    return (text == "-" or text.starts_with("- ") or text.starts_with("-\t"))

# A flow collection or quoted scalar can continue across physical lines.
fn complete(text: String) -> Bool:
    var quote = ""
    var depth = 0
    var index = 0
    let chars = text.split(separator: "")

    while index < chars.length:
        let c = chars.at(index).unwrap()

        if quote != "":
            if c == "\\" and quote == "\"": index = index + 1
            else if c == quote:
                if quote == "'" and chars.at(index + 1).unwrap_or("") == "'": index = (
                    index
                    + 1
                )
                else: quote = ""
        else if (
            (c == "\"" or c == "'")
            and (
                index == 0
                or " \t\n:[\{,".contains(
                    (chars.at((index - 1)).unwrap())
                )
            )
        ): quote = c
        else if c == "[" or c == "\{": depth = depth + 1
        else if c == "]" or c == "\}": depth = depth - 1

        index = index + 1

    return quote == "" and depth <= 0

fn inline_value(
    context: Context,
    text: String,
    depth: Int
) -> Result[YamlValue, YamlError]:
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
        and context.index < context.lines.length
    ):
        let next = context.lines.at(context.index).unwrap()
        # Keep quote state and physical empty lines when removing comments.
        let combined = joined.concat("\n").concat(next)
        let comment = boundary(text: combined, colon: false)

        if comment < 0: joined = combined
        else: joined = combined.slice(start: 0, end: comment).unwrap_or("")

        context.index = context.index + 1

    let flow = Flow(
        chars: joined.split(separator: ""),
        pos: 0,
        line: line,
        context: context,
        delimited: false
    )
    let result = try flow_value(flow: flow, depth: depth, key: false)
    flow_space(flow)
    if peek(flow) != "": return error(
        flow_invalid(flow: flow, reason: "unexpected trailing text")
    )

    return ok(result)

fn block_string(
    context: Context,
    header: String,
    base: Int
) -> Result[YamlValue, YamlError]:
    var mode = ""
    var explicit = 0
    var offset = 0
    # The header line was already consumed, so it is the previous line.
    let header_line = context.index
    let header_column = (
        context.lines.at(context.index - 1).unwrap_or("").index_of(
            header
        ).unwrap_or(0)
        + 1
    )

    for c in (
        header
        .slice(start: 1, end: header.scalar_length)
        .unwrap_or("")
        .split(separator: "")
    ):
        offset = offset + 1

        if (c == "+" or c == "-") and mode == "": mode = c
        else if "123456789".contains(c) and explicit == 0: explicit = (
            c
            .parse_int()
            .unwrap()
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
            probe < context.lines.length
            and context.lines.at(probe).unwrap().slice(
                start: indent(context.lines.at(probe).unwrap()),
                end: context.lines.at(probe).unwrap().scalar_length
            ).unwrap_or("") == ""
        ):
            let spaces = indent(context.lines.at(probe).unwrap())

            if spaces > blank_indent: blank_indent = spaces

            probe = probe + 1

        if probe < context.lines.length: content_indent = indent(
            (context.lines.at(probe).unwrap())
        )

        if content_indent <= base: content_indent = blank_indent

    let parts: List[String] = []

    while context.index < context.lines.length:
        let line = context.lines.at(context.index).unwrap()
        let spaces = indent(line)
        if (
            line.slice(start: spaces, end: line.scalar_length).unwrap_or(
                ""
            ) != ""
            and spaces < content_indent
        ):
            break

        parts.append(
            line.slice(
                start: content_indent,
                end: line.scalar_length
            ).unwrap_or("")
        )
        context.index = context.index + 1

    let builder = StringBuilder()
    var index = 0
    var content = false

    while index < parts.length:
        let part = parts.at(index).unwrap()

        if part != "": content = true

        builder.append(part)
        var separator = "\n"

        if (
            header.starts_with(">")
            and part != ""
            and not part.starts_with(" ")
            and not part.starts_with("\t")
            and index + 1 < parts.length
        ):
            var next_index = index + 1

            while next_index < parts.length and parts.at(next_index).unwrap() == "":
                next_index = next_index + 1

            if next_index < parts.length:
                let next = parts.at(next_index).unwrap()

                if not next.starts_with(" ") and not next.starts_with("\t"):
                    if next_index == index + 1: separator = " "
                    else: separator = ""

        if (
            index + 1 == parts.length
            and context.index == context.lines.length
            and not context.final_break
        ): separator = ""

        builder.append(separator)
        index = index + 1

    var result = builder.freeze()

    if mode != "+":
        let final_break = result.ends_with("\n")

        # Count the final run of line feeds once: trimming one scalar at a time is quadratic.
        let pieces = result.split(separator: "\n")
        var trailing = 0

        while (
            trailing < pieces.length
            and pieces.at(-1 - trailing).unwrap_or("x") == ""
        ): trailing = trailing + 1

        if trailing == pieces.length: trailing = trailing - 1

        result = (
            result
            .slice(start: 0, end: (result.scalar_length - trailing))
            .unwrap_or("")
        )

        if (mode != "-" and content and final_break): result = result.concat("\n")

    return ok(YamlValue.StringValue(result))

fn block_value(
    context: Context,
    text: String,
    base: Int,
    depth: Int,
    indentless: Bool
) -> Result[YamlValue, YamlError]:
    var remainder = text.trim_start()
    var anchor = ""

    if remainder.starts_with("&"):
        let flow = Flow(
            chars: remainder.split(separator: ""),
            pos: 1,
            line: context.index,
            context: context,
            delimited: false
        )
        anchor = try anchor_name(flow)
        remainder = (
            remainder
            .slice(start: flow.pos, end: remainder.scalar_length)
            .unwrap_or("")
            .trim_start()
        )

    var result = YamlValue.Null

    if remainder.starts_with("|") or remainder.starts_with(">"):
        let counted = try count(context: context, depth: depth)
        result = try block_string(
            context: context,
            header: remainder.trim_end(),
            base: base
        )
    else if remainder != "":
        if not "['\"\{*&!".contains(remainder.at(0).unwrap()):
            remainder = remainder.trim_end()
            let joined = StringBuilder()
            joined.append(remainder)
            var probe = context.index
            var blanks = 0

            while probe < context.lines.length:
                let line = context.lines.at(probe).unwrap()

                if line.trim() == "":
                    blanks = blanks + 1
                    probe = probe + 1
                    continue

                let next = uncomment(line)
                if next.trim() == "" or indent(next) <= base: break

                context.index = probe
                let next_indent = try indentation(context: context, text: next)
                if (
                    boundary(text: next, colon: true) >= 0
                    or sequence(next.trim_start())
                ): return error(
                    invalid(
                        context: context,
                        reason: "unexpected indented collection"
                    )
                )

                var separator = " "

                if blanks > 0:
                    separator = ""

                    while blanks > 0:
                        separator = separator.concat("\n")
                        blanks = blanks - 1

                joined.append(separator)
                joined.append(next.trim())
                probe = probe + 1
                context.index = probe

            remainder = joined.freeze()

        result = try inline_value(context: context, text: remainder, depth: depth)
    else:
        skip(context)

        if context.index < context.lines.length:
            let line = uncomment(context.lines.at(context.index).unwrap())
            let next_indent = try indentation(context: context, text: line)

            if (
                next_indent > base
                or (
                    indentless
                    and next_indent == base
                    and sequence(line.trim_start())
                )
            ):
                result = try block(context: context, base: next_indent, depth: depth)
            else:
                let counted = try count(context: context, depth: depth)
        else:
            let counted = try count(context: context, depth: depth)

    if anchor != "": context.anchors.add(key: anchor, value: result)

    return ok(result)

fn pad(width: Int) -> String:
    let builder = StringBuilder()
    var spaces = width

    while spaces > 0:
        builder.append(" ")
        spaces = spaces - 1

    return builder.freeze()

# Columns of the nested sequence levels opened by consecutive compact `- ` indicators.
fn nested_columns(line: String, base: Int) -> List[Int]:
    let chars = line.split(separator: "")
    let columns: List[Int] = []
    var marker = base

    while chars.at(marker).unwrap_or("") == "-":
        var next = marker + 1

        while chars.at(next).unwrap_or("") == " ": next = next + 1

        if next == marker + 1 or chars.at(next).unwrap_or("") != "-": break

        let after = chars.at(next + 1).unwrap_or("")
        if (after != "" and after != " " and after != "\t"): break

        columns.append(next)
        marker = next

    return columns

fn sequence_items(
    context: Context,
    values: List[YamlValue],
    base: Int,
    depth: Int
) -> Result[Unit, YamlError]:
    while context.index < context.lines.length:
        skip(context)
        if context.index >= context.lines.length: break

        let line = uncomment(context.lines.at(context.index).unwrap())
        let line_indent = try indentation(context: context, text: line)
        if line_indent < base: break
        if line_indent != base or not sequence(line.trim_start()): break

        let item = (
            line
            .trim_start()
            .slice(start: 1, end: (line.trim_start().scalar_length))
            .unwrap_or("")
            .trim_start()
        )

        let chain = nested_columns(line: line, base: base)

        if chain.length > 0:
            # A run of compact sequence indicators (`- - x`) opens one level per
            # indicator. Scan the line once and rewrite it once instead of per level.
            let innermost = chain.at(chain.length - 1).unwrap()
            let frames: List[List[YamlValue]] = []
            var level = 1

            while level <= chain.length:
                let counted = try count(context: context, depth: (depth + level))
                frames.append([])
                level = level + 1

            (
                context
                .lines
                .set(
                    index: context.index,
                    value: pad(innermost).concat(
                        (
                            line
                            .slice(
                                start: innermost,
                                end: line.scalar_length
                            )
                            .unwrap_or("")
                        )
                    )
                )
            )
            level = chain.length
            var nested = frames.at(level - 1).unwrap()
            let ran = try sequence_items(
                context: context,
                values: nested,
                base: innermost,
                depth: (depth + level)
            )
            var value = YamlValue.ArrayValue(nested)
            level = level - 1

            while level >= 1:
                nested = frames.at(level - 1).unwrap()
                nested.append(value)
                let resumed = try sequence_items(
                    context: context,
                    values: nested,
                    base: chain.at(level - 1).unwrap(),
                    depth: (depth + level)
                )
                value = YamlValue.ArrayValue(nested)
                level = level - 1

            values.append(value)
        else if sequence(item) or boundary(text: item, colon: true) >= 0:
            # Treat a compact mapping/sequence as a virtual indented first line.
            # Its column follows the indicator, so extra spaces move the nested base.
            let marker = (
                line
                .trim_start()
                .slice(
                    start: 1,
                    end: (line.trim_start().scalar_length)
                )
                .unwrap_or("")
            )
            var gap = indent(marker)

            if gap == 0: gap = 1

            let column = base + 1 + gap
            (context.lines.set(index: context.index, value: pad(column).concat(item)))
            values.append(try block(context: context, base: column, depth: (depth + 1)))
        else:
            context.index = context.index + 1
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

fn block(context: Context, base: Int, depth: Int) -> Result[YamlValue, YamlError]:
    skip(context)
    let first = uncomment(context.lines.at(context.index).unwrap()).trim_start()
    if first.starts_with("?"): return error(
        YamlError.UnsupportedFeature(
            line: (context.index + 1),
            reason: "explicit mapping keys are unsupported"
        )
    )

    if sequence(first):
        let counted = try count(context: context, depth: depth)
        let values: List[YamlValue] = []
        let ran = try sequence_items(
            context: context,
            values: values,
            base: base,
            depth: depth
        )
        return ok(YamlValue.ArrayValue(values))

    if boundary(text: first, colon: true) >= 0:
        let counted = try count(context: context, depth: depth)
        let values = Map[String, YamlValue]()
        let explicit = Set[String]()

        while context.index < context.lines.length:
            skip(context)
            if context.index >= context.lines.length: break

            let line = uncomment(context.lines.at(context.index).unwrap())
            let line_indent = try indentation(context: context, text: line)
            if line_indent != base or sequence(line.trim_start()): break

            let content = line.trim_start()
            let colon = boundary(text: content, colon: true)
            if colon < 0: break

            var name = content.slice(start: 0, end: colon).unwrap_or("").trim()

            let quoted_key = name.starts_with("\"") or name.starts_with("'")

            if quoted_key:
                let flow = Flow(
                    chars: name.split(separator: ""),
                    pos: 0,
                    line: (context.index + 1),
                    context: context,
                    delimited: false
                )
                name = try quoted(flow)
                if flow.pos != flow.chars.length: return error(
                    invalid(
                        context: context,
                        reason: "invalid quoted key"
                    )
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
                invalid(
                    context: context,
                    reason: "duplicate mapping key"
                )
            )

            explicit.add(name)
            let text = (
                content
                .slice(start: colon + 1, end: content.scalar_length)
                .unwrap_or("")
                .trim_start()
            )
            let key_line = context.index + 1
            context.index = context.index + 1
            let value = try block_value(
                context: context,
                text: text,
                base: base,
                depth: (depth + 1),
                indentless: true
            )

            if name == "<<" and not quoted_key:
                let merged = try merge(
                    line: key_line,
                    column: line_indent + 1,
                    target: values,
                    value: value
                )
            else:
                values.add(key: name, value: value)

        return ok(YamlValue.ObjectValue(values))

    context.index = context.index + 1
    return block_value(
        context: context,
        text: first,
        # A scalar or anchor on its own line may continue at the same indentation.
        base: base - 1,
        depth: depth,
        indentless: false
    )

fn validate(context: Context, value: YamlValue, depth: Int) -> Result[Unit, YamlError]:
    let counted = try count(context: context, depth: depth)

    match value:
        ArrayValue(values):
            for item in values: let valid = try validate(
                context: context,
                value: item,
                depth: (depth + 1)
            )

        ObjectValue(values):
            for entry in values: let valid = try validate(
                context: context,
                value: entry.value,
                depth: (depth + 1)
            )

        _: let ignored = unit

    return ok(unit)

# Parses a YAML document. Unsupported YAML features and invalid input include source locations.
export fn parse(
    text: String,
    limits: Optional[YamlLimits] = none
) -> Result[YamlValue, YamlError]:
    var options = YamlLimits()

    match limits:
        none: let ignored = unit
        some(value): options = value

    for limit in [options.max_bytes, options.max_depth, options.max_values]:
        match limit:
            none: let ignored = unit

            some(value):
                if value < 0: return error(YamlError.InvalidInput)

    if not within(value: text.byte_length, limit: options.max_bytes): return error(
        YamlError.LimitExceeded
    )

    var normalized = (
        text
        .replace(old: "\r\n", new: "\n", max_replacements: text.byte_length)
        .replace(old: "\r", new: "\n", max_replacements: text.byte_length)
    )

    if normalized.starts_with("\u{feff}"): normalized = (
        normalized
        .slice(start: 1, end: normalized.scalar_length)
        .unwrap_or("")
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
        lines: normalized.split(separator: "\n"),
        final_break: normalized.ends_with("\n"),
        index: 0,
        limits: options,
        values: 0,
        anchors: Map[String, YamlValue]()
    )

    # split's synthetic terminal empty line is not scalar content.
    if normalized.ends_with("\n"): context.lines.remove(context.lines.length - 1)

    skip(context)

    if (
        context.index < context.lines.length
        and context.lines.at(context.index).unwrap().starts_with("%")
    ):
        if uncomment(context.lines.at(context.index).unwrap()) != "%YAML 1.2": return error(
            YamlError.UnsupportedFeature(
                line: (context.index + 1),
                reason: "only the YAML 1.2 directive is supported"
            )
        )

        context.index = context.index + 1
        skip(context)
        if (
            context.index >= context.lines.length
            or uncomment(
                (context.lines.at(context.index).unwrap())
            ) != "---"
        ): return error(
            invalid(
                context: context,
                reason: "directive requires document start"
            )
        )

    # Content after the marker on the same line starts the document body.
    if (
        context.index < context.lines.length
        and context.lines.at(context.index).unwrap().starts_with("--- ")
    ):
        let line = context.lines.at(context.index).unwrap()
        let rest = line.slice(start: 4, end: line.scalar_length).unwrap_or("")

        if not rest.trim().starts_with("#"): (
            context
            .lines
            .splice(
                start: context.index,
                delete_count: 1,
                replacement: ["---", rest]
            )
        )

    if (
        context.index < context.lines.length
        and uncomment((context.lines.at(context.index).unwrap())) == "---"
    ):
        context.index = context.index + 1
        skip(context)

    var result = YamlValue.Null

    if (
        context.index < context.lines.length
        and uncomment((context.lines.at(context.index).unwrap())) != "..."
    ):
        result = try block(
            context: context,
            base: try indentation(
                context: context,
                text: (context.lines.at(context.index).unwrap())
            ),
            depth: 1
        )

    skip(context)

    if (
        context.index < context.lines.length
        and uncomment((context.lines.at(context.index).unwrap())) == "..."
    ):
        context.index = context.index + 1
        skip(context)

    if context.index != context.lines.length: return error(
        invalid(
            context: context,
            reason: "unexpected indentation or additional document"
        )
    )
    if options.max_depth.is_none and options.max_values.is_none: return ok(result)

    context.values = 0
    let valid = try validate(context: context, value: result, depth: 1)
    return ok(result)

fn hex4(code: Int) -> String:
    var digits = code.to_string(16)

    while digits.length < 4: digits = "0".concat(digits)

    return digits

fn quote_text(text: String) -> String:
    let result = StringBuilder()
    result.append("\"")

    for c in text.chars():
        let code = c.scalar_at(0).unwrap()

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

fn format_key(key: String) -> String:
    var plain = key != ""

    for c in key.chars():
        if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(
            c
        ): plain = false

    if plain and "0123456789-".contains(key.chars().first.unwrap()): plain = false

    if (
        plain
        and [
            "null",
            "true",
            "false",
            "yes",
            "no",
            "on",
            "off",
            "y",
            "n"
        ].contains(key.lower())
    ): plain = false

    if plain: return key

    return quote_text(key)

# A number keeps its original token, so it must resolve back to a number.
fn valid_number(text: String) -> Bool:
    match parse(text: text):
        ok(parsed): return parsed == YamlValue.NumberValue(text)
        error(_): return false

fn scalar_text(value: YamlValue) -> Result[String, YamlError]:
    match value:
        Null: return ok("null")
        BoolValue(flag): return ok(flag.toString())
        StringValue(text): return ok(quote_text(text))

        NumberValue(text):
            if not valid_number(text): return error(YamlError.InvalidInput)

            return ok(text)

        ArrayValue(values):
            if values.is_empty: return ok("[]")

            return ok("")

        ObjectValue(values):
            if values.is_empty: return ok("\{\}")

            return ok("")

fn is_block(value: YamlValue) -> Bool:
    match value:
        ArrayValue(values): return not values.is_empty
        ObjectValue(values): return not values.is_empty
        _: return false

fn emit_block(
    out: StringBuilder,
    value: YamlValue,
    indent: String
) -> Result[Unit, YamlError]:
    match value:
        ArrayValue(values):
            for item in values:
                if is_block(item):
                    out.append(indent.concat("-\n"))
                    try emit_block(out: out, value: item, indent: indent.concat("  "))
                else:
                    let text = try scalar_text(item)
                    out.append(indent.concat("- ").concat(text).concat("\n"))

            return ok(unit)

        ObjectValue(values):
            for entry in values.entries():
                let key = format_key(entry.key)

                if is_block(entry.value):
                    out.append(indent.concat(key).concat(":\n"))
                    try emit_block(
                        out: out,
                        value: entry.value,
                        indent: indent.concat("  ")
                    )
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
) -> Result[String, YamlError]:
    match max_bytes:
        none: let ignored = unit

        some(limit):
            if limit < 0: return error(YamlError.InvalidInput)

    let out = StringBuilder()

    if is_block(value): try emit_block(out: out, value: value, indent: "")
    else:
        let text = try scalar_text(value)
        out.append(text.concat("\n"))

    let text = out.freeze()

    if not within(value: text.byte_length, limit: max_bytes): return error(
        YamlError.LimitExceeded
    )

    return ok(text)
