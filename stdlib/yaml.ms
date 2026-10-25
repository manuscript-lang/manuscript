# Configuration-oriented YAML 1.2 parser implemented in Manuscript.
from "@std/math.ms" import parse_int
from "@std/string.ms" import from_scalars, StringBuilder

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
# Fields left none add no budget. Calling `parse` without any limits applies depth 10,000 and 1,000,000 values; pass a `YamlLimits` to change that.
export type YamlLimits:
    # Maximum UTF-8 input bytes before line-ending normalization; none adds no budget.
    max_bytes: Optional[Int] = none
    # Maximum value depth, including scalar leaves, with the root at one.
    max_depth: Optional[Int] = none
    # Maximum containers and leaves, excluding keys; aliases count at each checked occurrence.
    max_values: Optional[Int] = none

impl Error for YamlError:
    # Formats parser positions and reason text; match the typed fields for programmatic handling.
    def message() -> String:
        match self:
            case InvalidInput: return "invalid YAML input"
            case InvalidData(line, column, reason): return f"YAML {line}:{column}: {reason}"
            case UnsupportedFeature(line, reason): return f"YAML {line}: {reason}"
            case LimitExceeded: return "YAML limit exceeded"

type Context:
    lines: List[String]
    final_break: Bool
    index: Int
    limits: YamlLimits
    values: Int
    anchors: Map[String, YamlValue]
    sizes: Map[String, Int]

type Flow:
    chars: List[String]
    pos: Int
    line: Int
    context: Context
    delimited: Bool

# Limits applied when `parse` is called without any: deep nesting and alias expansion are
# the usual resource attacks. Pass a `YamlLimits` (even an empty one) to lift or change them.
def default_limits() -> YamlLimits:
    return YamlLimits(max_depth: some(10000), max_values: some(1000000))

def within(value: Int, limit: Optional[Int]) -> Bool:
    if let maximum = limit:
        return value <= maximum

    return True

# Number of containers and leaves in a value, excluding keys.
def tree_size(value: YamlValue) -> Int:
    var total = 1

    match value:
        case ArrayValue(values):
            for item in values: total += tree_size(item)
        case ObjectValue(values):
            for entry in values: total += tree_size(entry.value.clone())
        case _: ()

    return total

# Records an anchor and the size of its value so aliases can be charged before they are copied.
def define_anchor(var context: Context, name: String, value: YamlValue) -> Unit:
    context.anchors.add(name.clone(), value.clone())
    context.sizes.add(name, tree_size(value))

# Counts an alias expansion against the value budget before the aliased value is copied, so
# nested aliases cannot grow exponentially ahead of the limit.
def charge(var context: Context, size: Int) -> Result[Unit, YamlError]:
    context.values += size
    if not within(context.values, context.limits.max_values): return error(
        YamlError.LimitExceeded
    )

    return ok(())

def count(var context: Context, depth: Int) -> Result[Unit, YamlError]:
    if not within(depth, context.limits.max_depth): return error(
        YamlError.LimitExceeded
    )

    context.values += 1
    if not within(context.values, context.limits.max_values): return error(
        YamlError.LimitExceeded
    )

    return ok(())

def invalid(context: Context, reason: String) -> YamlError:
    return YamlError.InvalidData(line: context.index + 1, column: 1, reason: reason)

def peek(flow: Flow) -> String:
    return flow.chars.get(flow.pos, default: "").clone()

def advance(var flow: Flow) -> String:
    let c = peek(flow)
    if c != "": flow.pos += 1
    return c.clone()

def flow_space(var flow: Flow) -> Unit:
    while (peek(flow) == " " or peek(flow) == "\t" or peek(flow) == "\n"): advance(
        var flow
    )

def flow_invalid(flow: Flow, reason: String) -> YamlError:
    return YamlError.InvalidData(line: flow.line, column: flow.pos + 1, reason: reason)

# The first physical break folds to a space, or is removed before empty lines.
# An escaped first break is removed even when no empty lines follow it.
def folded_break(var flow: Flow, escaped: Bool) -> String:
    var result = ""

    while True:
        while peek(flow) == " " or peek(flow) == "\t": advance(var flow)
        if peek(flow) != "\n": break

        advance(var flow)
        result = result.concat("\n")

    if result == "" and not escaped: return " "

    return result

def quoted(var flow: Flow) -> Result[String, YamlError]:
    let quote = advance(var flow)

    # Append through a builder: per-character concatenation is quadratic on long strings.
    var result = StringBuilder()
    var whitespace = StringBuilder()

    while True:
        let c = advance(var flow)
        if c == "": return error(flow_invalid(flow, "unterminated string"))

        if c == quote:
            result.append(whitespace.freeze())
            whitespace = StringBuilder()

            if quote == "'" and peek(flow) == "'":
                advance(var flow)
                result.append("'")
                continue

            return ok(result.freeze())

        if c == "\n":
            whitespace = StringBuilder()
            result.append(folded_break(var flow, escaped: False))
            continue

        if c == " " or c == "\t":
            whitespace.append(c)
            continue

        result.append(whitespace.freeze())
        whitespace = StringBuilder()

        if c != "\\" or quote == "'":
            result.append(c)
            continue

        let escaped = advance(var flow)

        if escaped == "\n":
            result.append(folded_break(var flow, escaped: True))
        elif escaped == "0": result.append(f"\u{0}")
        elif escaped == "a": result.append(f"\u{7}")
        elif escaped == "b": result.append(f"\u{8}")
        elif escaped == "t" or escaped == "\t": result.append("\t")
        elif escaped == "n": result.append("\n")
        elif escaped == "v": result.append(f"\u{b}")
        elif escaped == "f": result.append(f"\u{c}")
        elif escaped == "r": result.append("\r")
        elif escaped == "e": result.append(f"\u{1b}")
        elif (escaped == " " or escaped == "\"" or escaped == "/" or escaped == "\\"): result.append(
            escaped
        )
        elif escaped == "N": result.append(f"\u{85}")
        elif escaped == "_": result.append(f"\u{a0}")
        elif escaped == "L": result.append(f"\u{2028}")
        elif escaped == "P": result.append(f"\u{2029}")
        elif (escaped == "x" or escaped == "u" or escaped == "U"):
            var count = 2
            if escaped == "u": count = 4
            if escaped == "U": count = 8

            var hex = ""

            while count > 0:
                let digit = advance(var flow)
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

def digit_text(text: String) -> Bool:
    if text == "": return False

    for c in text.split(""):
        if not "0123456789".contains(c): return False
    return True

def numeric(text: String) -> Bool:
    var clean = text.clone()
    if clean.starts_with("+") or clean.starts_with("-"): clean = (
        clean
        .slice(1, clean.scalar_length())
        .get("")
    )
    if (clean == ".inf" or clean == ".Inf" or clean == ".INF"): return True
    if (text == ".nan" or text == ".NaN" or text == ".NAN"): return True

    if clean.starts_with("0x") or clean.starts_with("0o"):
        if clean != text: return False

        var alphabet = "01234567"
        if clean.starts_with("0x"): alphabet = "0123456789abcdefABCDEF"

        let digits = clean.slice(2, clean.scalar_length()).get("")
        if digits == "": return False

        for c in digits.split(""):
            if not alphabet.contains(c): return False
        return True

    let exponent = clean.lower().split("e")
    if exponent.length() > 2: return False

    if exponent.length() == 2:
        var power = exponent.last().get()
        if power.starts_with("+") or power.starts_with("-"): power = (
            power
            .slice(1, power.scalar_length())
            .get("")
        )
        if not digit_text(power): return False

    let mantissa = exponent.first().get().split(".")
    if mantissa.length() > 2: return False
    if mantissa.length() == 1: return digit_text(mantissa.first().get())

    let whole = mantissa.first().get()
    let fraction = mantissa.last().get()
    if whole == "" and fraction == "": return False

    return (
        (whole == "" or digit_text(whole))
        and (fraction == "" or digit_text(fraction))
    )

def plain(text: String) -> YamlValue:
    if (text == "" or text == "~" or text == "null" or text == "Null" or text == "NULL"): return YamlValue.Null
    if (text == "true" or text == "True" or text == "TRUE"): return YamlValue.BoolValue(
        True
    )
    if (text == "false" or text == "False" or text == "FALSE"): return YamlValue.BoolValue(
        False
    )
    if numeric(text.clone()): return YamlValue.NumberValue(text)

    return YamlValue.StringValue(text)

def anchor_name(var flow: Flow) -> Result[String, YamlError]:
    var name = ""
    while peek(flow) != "" and not " \t\n,[]{}".contains(peek(flow)):
        name = name.concat(advance(var flow))
    if name == "": return error(flow_invalid(flow, "empty anchor name"))

    return ok(name)

def merge(
    line: Int,
    column: Int,
    var target: Map[String, YamlValue],
    value: YamlValue
) -> Result[Unit, YamlError]:
    let values = match value:
        case ObjectValue(entries):
            for entry in entries:
                if not target.contains(entry.key): target.add(
                    entry.key.clone(), entry.value.clone()
                )
            return ok(())
        case ArrayValue(values): values
        case _: return error(
            YamlError.InvalidData(
                line: line, column: column, reason: "merge requires mappings"
            )
        )

    for item in values:
        match item:
            case ObjectValue(_): try merge(
                line: line, column: column, target: var target, value: item
            )
            case _: return error(
                YamlError.InvalidData(
                    line: line, column: column, reason: "merge requires mappings"
                )
            )

    return ok(())

# A plain scalar continued across lines folds each break into one space; blank lines stay breaks.
def fold_plain(text: String) -> String:
    if not text.contains("\n"): return text

    var result = ""
    var blanks = 0
    var first = True

    for line in text.split("\n"):
        let trimmed = line.trim()

        if trimmed == "":
            blanks += 1
            continue

        if first: result = trimmed.clone()
        elif blanks == 0: result = result.concat(" ").concat(trimmed)
        else:
            var breaks = ""
            var remaining = blanks

            while remaining > 0:
                breaks = breaks.concat("\n")
                remaining -= 1

            result = result.concat(breaks).concat(trimmed)

        blanks = 0
        first = False

    return result

def flow_value(var flow: Flow, depth: Int, key: Bool) -> Result[YamlValue, YamlError]:
    flow_space(var flow)
    if not key:
        try count(var flow.context, depth)

    let c = peek(flow)

    if c == "&":
        advance(var flow)

        let name = try anchor_name(var flow)
        flow.context.values -= 1

        let value = try flow_value(var flow, depth, key: False)
        define_anchor(var flow.context, name, value.clone())
        return ok(value)

    if c == "*":
        advance(var flow)

        let name = try anchor_name(var flow)
        if let size = flow.context.sizes.get(name):
            try charge(var flow.context, size)
        if let value = flow.context.anchors.get(name):
            return ok(value.clone())

        return error(flow_invalid(flow, "unknown or recursive alias"))

    if c == "!": return error(
        YamlError.UnsupportedFeature(
            line: flow.line, reason: "explicit tags are unsupported"
        )
    )
    if c == "\"" or c == "'": return ok(YamlValue.StringValue(try quoted(var flow)))

    if c == "[":
        flow.delimited = True
        if key: return error(
            YamlError.UnsupportedFeature(
                line: flow.line, reason: "complex mapping keys are unsupported"
            )
        )

        advance(var flow)

        var values: List[YamlValue] = []
        flow_space(var flow)

        while peek(flow) != "]":
            if peek(flow) == "" or peek(flow) == ",": return error(
                flow_invalid(flow, "expected flow sequence value")
            )

            values.append(try flow_value(var flow, depth + 1, key: False))
            flow_space(var flow)
            if peek(flow) == "]": break
            if advance(var flow) != ",": return error(
                flow_invalid(flow, "expected sequence comma")
            )

            flow_space(var flow)

        advance(var flow)
        return ok(YamlValue.ArrayValue(values))

    if c == "{":
        flow.delimited = True
        if key: return error(
            YamlError.UnsupportedFeature(
                line: flow.line, reason: "complex mapping keys are unsupported"
            )
        )

        advance(var flow)

        var values = Map[String, YamlValue]()
        var explicit = Set[String]()
        flow_space(var flow)

        while peek(flow) != "}":
            if peek(flow) == "": return error(
                flow_invalid(flow, "unterminated flow mapping")
            )

            let quoted_key = peek(flow) == "\"" or peek(flow) == "'"
            let parsed_key = try flow_value(var flow, depth, key: True)
            var name = ""

            match parsed_key:
                case StringValue(value): name = value
                case _: return error(
                    YamlError.UnsupportedFeature(
                        line: flow.line, reason: "mapping keys must be strings"
                    )
                )

            flow_space(var flow)

            var value = YamlValue.Null

            # A key with no colon, as in `{a, b: 1}`, maps to null.
            if peek(flow) == "," or peek(flow) == "}":
                try count(var flow.context, depth + 1)
            else:
                if advance(var flow) != ":": return error(
                    flow_invalid(flow, "expected mapping colon")
                )

                value = try flow_value(var flow, depth + 1, key: False)

            if explicit.contains(name): return error(
                flow_invalid(flow, "duplicate mapping key")
            )

            explicit.add(name.clone())

            if name == "<<" and not quoted_key:
                try merge(
                    line: flow.line, column: flow.pos + 1, target: var values,
                    value: value
                )
            else:
                values.add(name, value)

            flow_space(var flow)
            if peek(flow) == "}": break
            if advance(var flow) != ",": return error(
                flow_invalid(flow, "expected mapping comma")
            )

            flow_space(var flow)

        advance(var flow)
        return ok(YamlValue.ObjectValue(values))

    let start = flow.pos

    while (
        peek(flow) != ""
        and not ((flow.delimited or key) and ",[]{}".contains(peek(flow)))
        and not (key and peek(flow) == ":")
    ):
        if peek(flow) == ":" and flow.chars.get(flow.pos + 1, default: "") == " ": return error(
            flow_invalid(flow, "unexpected mapping colon")
        )

        advance(var flow)

    # Slice once: appending each character to a string is quadratic on long scalars.
    var text = (flow.chars.slice(start, flow.pos).get([]).join("").trim())
    if flow.delimited: text = fold_plain(text)
    if key: return ok(YamlValue.StringValue(text))

    return ok(plain(text))

def quoted_or_nested(text: String) -> Bool:
    return (
        text.contains("\"")
        or text.contains("'")
        or text.contains("[")
        or text.contains("{")
    )

# boundary for text with no quotes or brackets: the first marker that follows a blank (or ends the text) wins.
def plain_boundary(text: String, colon: Bool) -> Int:
    var marker = "#"
    if colon: marker = ":"

    var offset = 0

    while True:
        let rest = (text.slice_scalars(offset, text.scalar_length()).get(""))
        let found = rest.index_of(marker).get(-1)
        if found < 0: return -1

        let at = offset + found
        let before = text.get(at - 1, default: "")
        let after = text.get(at + 1, default: "")
        if colon and (after == "" or after == " " or after == "\t"): return at
        if not colon and (at == 0 or before == " " or before == "\t"): return at

        offset = at + 1

# Find a mapping colon or comment outside quoted/flow values.
def boundary(text: String, colon: Bool) -> Int:
    # Without the marker nothing can match; without quotes or brackets the first candidate decides.
    if colon and not text.contains(":"): return -1
    if not colon and not text.contains("#"): return -1
    if not quoted_or_nested(text): return plain_boundary(text, colon)

    let chars = text.split("")
    var quote = ""
    var depth = 0
    var index = 0

    while index < chars.length():
        let c = chars.get(index)

        if quote != "":
            if c == "\\" and quote == "\"": index += 1
            elif c == quote:
                if quote == "'" and chars.get(index + 1, default: "") == "'": index = (
                    index
                    + 1
                )
                else: quote = ""
        elif (
            (c == "\"" or c == "'")
            and (
                index == 0
                or " \t\n:[{,".contains((chars.get((index - 1))))
            )
        ): quote = c.clone()
        elif c == "[" or c == "{": depth += 1
        elif c == "]" or c == "}": depth -= 1
        elif (
            colon
            and c == ":"
            and depth == 0
            and (
                index + 1 == chars.length()
                or chars.get((index + 1), default: "") == " "
                or chars.get((index + 1), default: "") == "\t"
            )
        ):
            return index
        elif (
            not colon
            and c == "#"
            and (
                index == 0
                or chars.get(index - 1, default: "") == " "
                or chars.get((index - 1), default: "") == "\t"
            )
        ):
            return index

        index += 1

    return -1

def uncomment(text: String) -> String:
    let index = boundary(text, colon: False)

    if index < 0:
        if not complete(text): return text.clone()

        return text.trim_end().clone()

    return text.slice(0, index).get("").trim_end().clone()

def indent(text: String) -> Int:
    var result = 0
    while text.get(result, default: "") == " ": result += 1
    return result

def indentation(context: Context, text: String) -> Result[Int, YamlError]:
    let spaces = indent(text)
    if text.get(spaces, default: "") == "\t": return error(
        invalid(context, "tabs cannot indent YAML")
    )

    return ok(spaces)

def skip(var context: Context) -> Unit:
    while (
        context.index < context.lines.length()
        and uncomment((context.lines.get(context.index))).trim() == ""
    ): context.index = (context.index + 1)

def sequence(text: String) -> Bool:
    return (text == "-" or text.starts_with("- ") or text.starts_with("-\t"))

# A flow collection or quoted scalar can continue across physical lines.
def complete(text: String) -> Bool:
    if not quoted_or_nested(text): return True

    var quote = ""
    var depth = 0
    var index = 0
    let chars = text.split("")

    while index < chars.length():
        let c = chars.get(index)

        if quote != "":
            if c == "\\" and quote == "\"": index += 1
            elif c == quote:
                if quote == "'" and chars.get(index + 1, default: "") == "'": index = (
                    index
                    + 1
                )
                else: quote = ""
        elif (
            (c == "\"" or c == "'")
            and (
                index == 0
                or " \t\n:[{,".contains((chars.get((index - 1))))
            )
        ): quote = c.clone()
        elif c == "[" or c == "{": depth += 1
        elif c == "]" or c == "}": depth -= 1

        index += 1

    return quote == "" and depth <= 0

def inline_value(var context: Context, text: String, depth: Int) -> Result[
    YamlValue, YamlError
]:
    var joined = text.clone()
    let line = context.index
    let structured = (
        text.starts_with("[")
        or text.starts_with("{")
        or text.starts_with("\"")
        or text.starts_with("'")
        or text.starts_with("&")
    )

    while (
        structured
        and not complete(joined)
        and context.index < context.lines.length()
    ):
        let next = context.lines.get(context.index)

        # Keep quote state and physical empty lines when removing comments.
        let combined = joined.concat("\n").concat(next)
        let comment = boundary(combined, colon: False)

        if comment < 0: joined = combined
        else: joined = combined.slice(0, comment).get("")

        context.index += 1

    # A flow value needs only the limits, counters and anchors, so it gets a context without
    # the document lines (copying them for every value made parsing quadratic).
    var flow = Flow(
        chars: joined.split(""),
        pos: 0,
        line: line,
        context: Context(
            lines: [], final_break: context.final_break, index: context.index,
            limits: context.limits, values: context.values,
            anchors: context.anchors.clone(), sizes: context.sizes.clone()
        ),
        delimited: False
    )
    let result = try flow_value(var flow, depth, key: False)
    flow_space(var flow)
    if peek(flow) != "": return error(flow_invalid(flow, "unexpected trailing text"))

    context.values = flow.context.values
    context.anchors = flow.context.anchors.clone()
    context.sizes = flow.context.sizes.clone()
    return ok(result)

def block_string(var context: Context, header: String, base: Int) -> Result[
    YamlValue, YamlError
]:
    var mode = ""
    var explicit = 0
    var offset = 0

    # The header line was already consumed, so it is the previous line.
    let header_line = context.index
    let header_column = (
        context.lines.get(context.index - 1, default: "").index_of(header).get(
            0
        )
        + 1
    )

    for c in (header.slice(1, header.scalar_length()).get("").split("")):
        offset += 1

        if (c == "+" or c == "-") and mode == "": mode = c
        elif "123456789".contains(c) and explicit == 0: explicit = (c.parse_int().get())
        else: return error(
            YamlError.InvalidData(
                line: header_line, column: header_column + offset,
                reason: "invalid block scalar header"
            )
        )

    var content_indent = base + explicit
    let scan_start = context.index
    var probe = scan_start

    if explicit == 0:
        var blank_indent = base + 1

        while (
            probe < context.lines.length()
            and context.lines.get(probe).slice(
                indent(context.lines.get(probe)),
                context.lines.get(probe).scalar_length()
            ).get("") == ""
        ):
            let spaces = indent(context.lines.get(probe))
            if spaces > blank_indent: blank_indent = spaces
            probe += 1

        if probe < context.lines.length(): content_indent = indent(
            (context.lines.get(probe))
        )
        if content_indent <= base: content_indent = blank_indent

    var parts: List[String] = []

    while context.index < context.lines.length():
        let line = context.lines.get(context.index)
        let spaces = indent(line)
        if (
            line.slice(spaces, line.scalar_length()).get("") != ""
            and spaces < content_indent
        ):
            break

        parts.append(line.slice(content_indent, line.scalar_length()).get(""))
        context.index += 1

    var builder = StringBuilder()
    var index = 0
    var content = False

    while index < parts.length():
        let part = parts.get(index)
        if part != "": content = True
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
            while next_index < parts.length() and parts.get(next_index) == "":
                next_index += 1

            if next_index < parts.length():
                let next = parts.get(next_index)

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
        while (
            trailing < pieces.length()
            and pieces.get(-1 - trailing, default: "x") == ""
        ): trailing += 1
        if trailing == pieces.length(): trailing -= 1
        result = (result.slice(0, (result.scalar_length() - trailing)).get(""))
        if (mode != "-" and content and final_break): result = result.concat("\n")

    return ok(YamlValue.StringValue(result))

def block_value(
    var context: Context, text: String, base: Int, depth: Int, indentless: Bool
) -> Result[YamlValue, YamlError]:
    var remainder = text.trim_start().clone()
    var anchor = ""

    if remainder.starts_with("&"):
        var flow = Flow(
            chars: remainder.split(""), pos: 1, line: context.index,
            context: context.clone(), delimited: False
        )
        anchor = try anchor_name(var flow)
        remainder = (
            remainder
            .slice(flow.pos, remainder.scalar_length())
            .get("")
            .trim_start()
        )

    var result = YamlValue.Null

    if remainder.starts_with("|") or remainder.starts_with(">"):
        try count(var context, depth)
        result = try block_string(var context, remainder.trim_end(), base)
    elif remainder != "":
        if not "['\"{*&!".contains(remainder.get(0)):
            remainder = remainder.trim_end().clone()

            var joined = StringBuilder()
            joined.append(remainder)

            let scan_start = context.index
            var probe = scan_start
            var blanks = 0

            while probe < context.lines.length():
                let line = context.lines.get(probe)

                if line.trim() == "":
                    blanks += 1
                    probe += 1
                    continue

                let next = uncomment(line.clone())
                if next.trim() == "" or indent(next) <= base: break

                context.index = probe

                let _indent = try indentation(context, next)
                if (boundary(next, colon: True) >= 0 or sequence(next.trim_start())): return error(
                    invalid(
                        context, "unexpected indented collection"
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

        result = try inline_value(var context, remainder, depth)
    else:
        skip(var context)

        if context.index < context.lines.length():
            let line = uncomment(context.lines.get(context.index))
            let next_indent = try indentation(context, line)

            if (
                next_indent > base
                or (
                    indentless
                    and next_indent == base
                    and sequence(line.trim_start())
                )
            ):
                result = try block(var context, next_indent, depth)
            else:
                try count(var context, depth)
        else:
            try count(var context, depth)

    if anchor != "": define_anchor(var context, anchor, result.clone())
    return ok(result)

def pad(width: Int) -> String:
    var builder = StringBuilder()
    var spaces = width

    while spaces > 0:
        builder.append(" ")
        spaces -= 1

    return builder.freeze()

# Columns of the nested sequence levels opened by consecutive compact `- ` indicators.
def nested_columns(line: String, base: Int) -> List[Int]:
    let chars = line.split("")
    var columns: List[Int] = []
    var marker = base

    while chars.get(marker, default: "") == "-":
        var next = marker + 1
        while chars.get(next, default: "") == " ": next += 1
        if next == marker + 1 or chars.get(next, default: "") != "-": break

        let after = chars.get(next + 1, default: "")
        if (after != "" and after != " " and after != "\t"): break

        columns.append(next)
        marker = next

    return columns

def sequence_items(
    var context: Context, var values: List[YamlValue], base: Int, depth: Int
) -> Result[Unit, YamlError]:
    while context.index < context.lines.length():
        skip(var context)
        if context.index >= context.lines.length(): break

        let line = uncomment(context.lines.get(context.index))
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
            let innermost = chain.get(chain.length() - 1)
            var frames: List[List[YamlValue]] = []
            var level = 1

            while level <= chain.length():
                try count(var context, (depth + level))
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
                                innermost, line.scalar_length()
                            )
                            .get("")
                        )
                    )
                )
            )
            level = chain.length()

            var nested = frames.get(level - 1).clone().clone()
            try sequence_items(
                context: var context, values: var nested, base: innermost,
                depth: (depth + level)
            )

            var value = YamlValue.ArrayValue(nested)
            level -= 1

            while level >= 1:
                nested = frames.get(level - 1).clone()
                nested.append(value)
                try sequence_items(
                    context: var context, values: var nested,
                    base: chain.get(level - 1), depth: (depth + level)
                )
                value = YamlValue.ArrayValue(nested)
                level -= 1

            values.append(value)
        elif sequence(item) or boundary(item, colon: True) >= 0:
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
            values.append(try block(var context, column, (depth + 1)))
        else:
            context.index += 1
            values.append(
                try block_value(
                    context: var context, text: item, base: base, depth: (depth + 1),
                    indentless: False
                )
            )

    return ok(())

def block(var context: Context, base: Int, depth: Int) -> Result[YamlValue, YamlError]:
    skip(var context)

    let first = uncomment(context.lines.get(context.index)).trim_start()
    if first.starts_with("?"): return error(
        YamlError.UnsupportedFeature(
            line: (context.index + 1), reason: "explicit mapping keys are unsupported"
        )
    )

    if sequence(first):
        try count(var context, depth)

        var values: List[YamlValue] = []
        try sequence_items(
            context: var context, values: var values, base: base, depth: depth
        )
        return ok(YamlValue.ArrayValue(values))

    if boundary(first, colon: True) >= 0:
        try count(var context, depth)

        var values = Map[String, YamlValue]()
        var explicit = Set[String]()

        while context.index < context.lines.length():
            skip(var context)
            if context.index >= context.lines.length(): break

            let line = uncomment(context.lines.get(context.index))
            let line_indent = try indentation(context, line)
            if line_indent != base or sequence(line.trim_start()): break

            let content = line.trim_start()
            let colon = boundary(content, colon: True)
            if colon < 0: break

            var name = content.slice(0, colon).get("").trim()
            let quoted_key = name.starts_with("\"") or name.starts_with("'")

            if quoted_key:
                var flow = Flow(
                    chars: name.split(""), pos: 0, line: (context.index + 1),
                    context: context.clone(), delimited: False
                )
                name = try quoted(var flow)
                if flow.pos != flow.chars.length(): return error(
                    invalid(context, "invalid quoted key")
                )
            elif (
                name == ""
                or name.starts_with("[")
                or name.starts_with("{")
                or name.starts_with("!")
                or name.starts_with("&")
                or name.starts_with("*")
            ):
                return error(
                    YamlError.UnsupportedFeature(
                        line: context.index + 1, reason: "mapping keys must be strings"
                    )
                )

            if explicit.contains(name): return error(
                invalid(context, "duplicate mapping key")
            )

            explicit.add(name.clone())

            let text = (
                content
                .slice(colon + 1, content.scalar_length())
                .get("")
                .trim_start()
            )
            let key_line = context.index + 1
            context.index += 1

            let value = try block_value(
                context: var context, text: text, base: base, depth: (depth + 1),
                indentless: True
            )

            if name == "<<" and not quoted_key:
                try merge(
                    line: key_line, column: line_indent + 1, target: var values,
                    value: value
                )
            else:
                values.add(name, value)

        return ok(YamlValue.ObjectValue(values))

    context.index += 1
    return block_value(
        context: var context,
        text: first,
        # A scalar or anchor on its own line may continue at the same indentation.
        base: base - 1,
        depth: depth,
        indentless: False
    )

def validate(var context: Context, value: YamlValue, depth: Int) -> Result[
    Unit, YamlError
]:
    try count(var context, depth)

    match value:
        case ArrayValue(values):
            for item in values: try validate(var context, item, (depth + 1))
        case ObjectValue(values):
            for entry in values: try validate(
                var context, entry.value.clone(), (depth + 1)
            )
        case _: ()

    return ok(())

# Parses a YAML document. Unsupported YAML features and invalid input include source locations.
export def parse(
    text: String,
    limits: Optional[YamlLimits] = none
) -> Result[YamlValue, YamlError]:
    var options = default_limits()
    if let value = limits:
        options = value
    for limit in [options.max_bytes, options.max_depth, options.max_values]:
        if let value = limit:
            if value < 0: return error(YamlError.InvalidInput)
    if not within(text.byte_length(), options.max_bytes): return error(
        YamlError.LimitExceeded
    )

    var normalized = (text.replace("\r\n", "\n").replace("\r", "\n"))
    if normalized.starts_with(f"\u{feff}"): normalized = (
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
                    line: 1, column: 1, reason: "invalid control character"
                )
            )

    var context = Context(
        lines: normalized.split("\n"), final_break: normalized.ends_with("\n"),
        index: 0, limits: options, values: 0, anchors: Map[String, YamlValue](),
        sizes: Map[String, Int]()
    )

    # split's synthetic terminal empty line is not scalar content.
    if normalized.ends_with("\n"): context.lines.remove(context.lines.length() - 1)
    skip(var context)

    if (
        context.index < context.lines.length()
        and context.lines.get(context.index).starts_with("%")
    ):
        if uncomment(context.lines.get(context.index)) != "%YAML 1.2": return error(
            YamlError.UnsupportedFeature(
                line: (context.index + 1),
                reason: "only the YAML 1.2 directive is supported"
            )
        )

        context.index += 1
        skip(var context)
        if (
            context.index >= context.lines.length()
            or uncomment((context.lines.get(context.index))) != "---"
        ): return error(invalid(context, "directive requires document start"))

    # Content after the marker on the same line starts the document body.
    if (
        context.index < context.lines.length()
        and context.lines.get(context.index).starts_with("--- ")
    ):
        let line = context.lines.get(context.index)
        let rest = line.slice(4, line.scalar_length()).get("")
        if not rest.trim().starts_with("#"): (
            context
            .lines
            .splice(context.index, 1, ["---", rest])
        )

    if (
        context.index < context.lines.length()
        and uncomment((context.lines.get(context.index))) == "---"
    ):
        context.index += 1
        skip(var context)

    var result = YamlValue.Null
    if (
        context.index < context.lines.length()
        and uncomment((context.lines.get(context.index))) != "..."
    ):
        result = try block(
            var context, try indentation(context, (context.lines.get(context.index))), 1
        )
    skip(var context)

    if (
        context.index < context.lines.length()
        and uncomment((context.lines.get(context.index))) == "..."
    ):
        context.index += 1
        skip(var context)

    if context.index != context.lines.length(): return error(
        invalid(context, "unexpected indentation or additional document")
    )
    if options.max_depth.is_none() and options.max_values.is_none(): return ok(result)

    context.values = 0
    try validate(var context, result.clone(), 1)
    return ok(result)

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
        elif code < 32 or (code >= 127 and code <= 159):
            result.append("\\u")
            result.append(hex4(code))
        else: result.append(c)

    result.append("\"")
    return result.freeze()

def format_key(key: String) -> String:
    var plain = key != ""
    for c in key.chars():
        if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(
            c
        ): plain = False
    if plain and "0123456789-".contains(key.chars().first().get()): plain = False
    if (
        plain
        and [
            "null", "true", "false", "yes", "no", "on", "off", "y", "n"
        ].contains(key.lower())
    ): plain = False
    if plain: return key

    return quote_text(key)

# A number keeps its original token, so it must resolve back to a number.
def valid_number(text: String) -> Bool:
    if let parsed = parse(text): return parsed == YamlValue.NumberValue(text)

    return False

def scalar_text(value: YamlValue) -> Result[String, YamlError]:
    match value:
        case Null: return ok("null")
        case BoolValue(flag): return ok(flag.to_string())
        case StringValue(text): return ok(quote_text(text))
        case NumberValue(text):
            if not valid_number(text.clone()): return error(YamlError.InvalidInput)

            return ok(text)
        case ArrayValue(values):
            if values.is_empty(): return ok("[]")

            return ok("")
        case ObjectValue(values):
            if values.is_empty(): return ok("{}")

            return ok("")

def is_block(value: YamlValue) -> Bool:
    match value:
        case ArrayValue(values): return not values.is_empty()
        case ObjectValue(values): return not values.is_empty()
        case _: return False

def emit_block(var out: StringBuilder, value: YamlValue, indent: String) -> Result[
    Unit, YamlError
]:
    match value:
        case ArrayValue(values):
            for item in values:
                if is_block(item.clone()):
                    out.append(indent.concat("-\n"))
                    try emit_block(var out, item, indent.concat("  "))
                else:
                    let text = try scalar_text(item.clone())
                    out.append(indent.concat("- ").concat(text).concat("\n"))

            return ok(())
        case ObjectValue(values):
            for entry in values.entries():
                let key = format_key(entry.key.clone())

                if is_block(entry.value.clone()):
                    out.append(indent.concat(key).concat(":\n"))
                    try emit_block(var out, entry.value.clone(), indent.concat("  "))
                else:
                    let text = try scalar_text(entry.value.clone())
                    out.append(
                        indent.concat(key).concat(": ").concat(
                            text
                        ).concat("\n")
                    )

            return ok(())
        case _: return ok(())

# Serializes a YAML value in block style with double-quoted strings.
export def stringify(
    value: YamlValue,
    max_bytes: Optional[Int] = none
) -> Result[String, YamlError]:
    if let limit = max_bytes:
        if limit < 0: return error(YamlError.InvalidInput)

    var out = StringBuilder()

    if is_block(value.clone()): try emit_block(var out, value, "")
    else:
        let text = try scalar_text(value.clone())
        out.append(text.concat("\n"))

    let text = out.freeze()
    if not within(text.byte_length(), max_bytes): return error(YamlError.LimitExceeded)

    return ok(text)
