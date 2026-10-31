# Configuration-oriented YAML 1.2 parser implemented in Manuscript.
import Bytes from "@std/bytes.ms"
import parse_int from "@std/math.ms"
import from_scalars, StringBuilder from "@std/string.ms"

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
    max_bytes: Int?
    # Maximum value depth, including scalar leaves, with the root at one.
    max_depth: Int?
    # Maximum containers and leaves, excluding keys; aliases count at each checked occurrence.
    max_values: Int?

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
    sizes: Map[String, Int]
    # Per-line facts computed once from the document bytes. A simple line is ASCII with no tab,
    # quote, bracket, brace or `#`, no trailing space and no leading `?`, so its comment-free
    # text, indentation and mapping colon need no character-by-character scan.
    simple: List[Bool]
    blank: List[Bool]
    dash: List[Bool]
    ind: List[Int]
    col: List[Int]

type Flow:
    chars: List[String]
    codes: List[Int]
    pos: Int
    line: Int
    context: Context
    delimited: Bool

# YAML separates tokens with only space and tab; Unicode spaces such as U+00A0 are scalar content.
fn blank(code: Int) Bool:
    return code == 32 or code == 9

# `text` without leading spaces and tabs.
fn blank_trim_start(text: String) String:
    let count = text.scalar_length()
    var from = 0
    while from < count and blank(text.scalar_at(from, default: 0)):
        from += 1
    if from == 0: return text.clone()

    return text.slice_scalars(from, count).get("")

# `text` without trailing spaces and tabs.
fn blank_trim_end(text: String) String:
    var end = text.scalar_length()
    while end > 0 and blank(text.scalar_at(end - 1, default: 0)):
        end -= 1
    if end == text.scalar_length(): return text.clone()

    return text.slice_scalars(0, end).get("")

# `text` without leading and trailing spaces and tabs.
fn blank_trim(text: String) String:
    return blank_trim_end(blank_trim_start(text))

# Limits applied when `parse` is called without any: deep nesting and alias expansion are
# the usual resource attacks. Pass a `YamlLimits` (even an empty one) to lift or change them.
fn default_limits() YamlLimits:
    return YamlLimits(max_depth: 10000, max_values: 1000000)

fn within(value: Int, limit: Int?) Bool:
    if let maximum = limit:
        return value <= maximum

    return true

# Number of containers and leaves in a value, excluding keys.
fn tree_size(value: YamlValue) Int:
    var total = 1

    match value:
        ArrayValue(values):
            for item in values: total += tree_size(item)
        ObjectValue(values):
            for entry in values: total += tree_size(entry.value.clone())
        _: unit

    return total

# Records an anchor and the size of its value so aliases can be charged before they are copied.
fn define_anchor(var context: Context, name: String, value: YamlValue) Unit:
    context.anchors.add(name.clone(), value.clone())
    context.sizes.add(name, tree_size(value))

# Counts an alias expansion against the value budget before the aliased value is copied, so
# nested aliases cannot grow exponentially ahead of the limit.
fn charge(var context: Context, size: Int) Unit!YamlError:
    context.values += size
    if not within(context.values, context.limits.max_values): return error(
        YamlError.LimitExceeded
    )

    return ok(unit)

fn count(var context: Context, depth: Int) Unit!YamlError:
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
    return flow.chars.get(flow.pos, default: "").clone()

fn advance(var flow: Flow) String:
    let c = peek(flow)
    if c != "": flow.pos += 1
    return c.clone()

# The scalar value at the cursor, or 0 at the end; `codes` is empty for flows that only read quoted text.
fn cur(flow: Flow) Int:
    return flow.codes.get(flow.pos, default: 0)

fn step(var flow: Flow) Int:
    let code = cur(flow)
    if code != 0: flow.pos += 1
    return code

fn flow_space(var flow: Flow) Unit:
    while true:
        let code = cur(flow)
        if code != 32 and code != 9 and code != 10: break

        flow.pos += 1

fn flow_invalid(flow: Flow, reason: String) YamlError:
    return YamlError.InvalidData(line: flow.line, column: flow.pos + 1, reason: reason)

# The first physical break folds to a space, or is removed before empty lines.
# An escaped first break is removed even when no empty lines follow it.
fn folded_break(var flow: Flow, escaped: Bool) String:
    var result = ""

    while true:
        while peek(flow) == " " or peek(flow) == "\t": advance(var flow)
        if peek(flow) != "\n": break

        advance(var flow)
        result = result.concat("\n")

    if result == "" and not escaped: return " "

    return result

fn quoted(var flow: Flow) String!YamlError:
    let quote = advance(var flow)

    # Append through a builder: per-character concatenation is quadratic on long strings.
    var result = StringBuilder()
    var whitespace = StringBuilder()

    while true:
        let c = advance(var flow)
        if c == "": return error(flow_invalid(flow, "unterminated string"))

        if c == quote:
            result.append(whitespace.build())
            whitespace = StringBuilder()

            if quote == "'" and peek(flow) == "'":
                advance(var flow)
                result.append("'")
                continue

            return ok(result.build())

        if c == "\n":
            whitespace = StringBuilder()
            result.append(folded_break(var flow, escaped: false))
            continue

        if c == " " or c == "\t":
            whitespace.append(c)
            continue

        result.append(whitespace.build())
        whitespace = StringBuilder()

        if c != "\\" or quote == "'":
            result.append(c)
            continue

        let escaped = advance(var flow)

        if escaped == "\n":
            result.append(folded_break(var flow, escaped: true))
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

fn digit_text(text: String) Bool:
    if text == "": return false

    for code in text.scalar_values():
        if code < 48 or code > 57: return false
    return true

fn numeric(text: String) Bool:
    let first = text.scalar_at(0, default: 0)
    if not (first == 43 or first == 45 or first == 46 or (first >= 48 and first <= 57)): return false

    var clean = text.clone()
    if clean.starts_with("+") or clean.starts_with("-"): clean = clean.slice(
        1, clean.scalar_length()
    ).get("")
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
        if power.starts_with("+") or power.starts_with("-"): power = power.slice(
            1, power.scalar_length()
        ).get("")
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
    if numeric(text.clone()): return YamlValue.NumberValue(text)

    return YamlValue.StringValue(text)

fn anchor_name(var flow: Flow) String!YamlError:
    var name = ""
    while peek(flow) != "" and not " \t\n,[]\{\}".contains(peek(flow)):
        name = name.concat(advance(var flow))
    if name == "": return error(flow_invalid(flow, "empty anchor name"))

    return ok(name)

fn merge(
    line: Int,
    column: Int,
    var target: Map[String, YamlValue],
    value: YamlValue
) Unit!YamlError:
    let values = match value:
        ObjectValue(entries):
            for entry in entries:
                if not target.contains(entry.key): target.add(
                    entry.key.clone(), entry.value.clone()
                )
            return ok(unit)
        ArrayValue(values): values
        _: return error(
            YamlError.InvalidData(
                line: line, column: column, reason: "merge requires mappings"
            )
        )

    for item in values:
        match item:
            ObjectValue(_): try merge(
                line: line, column: column, target: var target, value: item
            )
            _: return error(
                YamlError.InvalidData(
                    line: line, column: column, reason: "merge requires mappings"
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
        let trimmed = blank_trim(line)

        if trimmed == "":
            blanks += 1
            continue

        if first: result = trimmed.clone()
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

# A scalar, alias or quoted string at the cursor, whose first code is `c`.
fn flow_leaf(var flow: Flow, c: Int, key: Bool) YamlValue!YamlError:
    if c == 42:
        advance(var flow)

        let name = try anchor_name(var flow)
        if let size = flow.context.sizes.get(name):
            try charge(var flow.context, size)
        if let value = flow.context.anchors.get(name):
            return ok(value.clone())

        return error(flow_invalid(flow, "unknown or recursive alias"))

    if c == 33: return error(
        YamlError.UnsupportedFeature(
            line: flow.line, reason: "explicit tags are unsupported"
        )
    )
    if c == 34 or c == 39: return ok(YamlValue.StringValue(try quoted(var flow)))

    let start = flow.pos

    while true:
        let code = cur(flow)
        if code == 0: break
        if (
            (flow.delimited or key)
            and (
                code == 44
                or code == 91
                or code == 93
                or code == 123
                or code == 125
            )
        ): break
        if key and code == 58: break
        if code == 58 and flow.codes.get(flow.pos + 1, default: 0) == 32: return error(
            flow_invalid(flow, "unexpected mapping colon")
        )

        flow.pos += 1

    # Slice once: appending each character to a string is quadratic on long scalars.
    var text = blank_trim(flow.chars.slice(start, flow.pos).get([]).join(""))
    if text.starts_with("?") and (text.length() == 1 or " \t".contains(text.get(1))): return error(
        YamlError.UnsupportedFeature(
            line: flow.line, reason: "explicit mapping keys are unsupported"
        )
    )
    if not plain_may_start(text): return error(
        flow_invalid(
            flow, "a plain scalar cannot start with an indicator character"
        )
    )

    if flow.delimited: text = fold_plain(text)
    if key: return ok(YamlValue.StringValue(text))

    return ok(plain(text))

# Stores a finished mapping value under `name`.
fn flow_entry(
    var flow: Flow, name: String, quoted_key: Bool, var entries: Map[String, YamlValue],
    var explicit: Set[String], value: YamlValue
) Unit!YamlError:
    if explicit.contains(name): return error(
        flow_invalid(flow, "duplicate mapping key")
    )

    explicit.add(name.clone())

    if name == "<<" and not quoted_key:
        try merge(
            line: flow.line, column: flow.pos + 1, target: var entries, value: value
        )
    else:
        entries.add(name.clone(), value)

    return ok(unit)

# Parses a flow value. Nested sequences and mappings are parsed with explicit stacks, not by
# recursion, so the nesting depth is bounded by the depth limit and not by the call stack. Only
# a mapping key recurses, and a key cannot be a container.
fn flow_value(var flow: Flow, depth: Int, key: Bool) YamlValue!YamlError:
    # The open containers, innermost last: kind (1 sequence, 2 mapping), depth, anchors, and
    # the entries so far. The innermost one is held in the variables below `parents`.
    var kinds: List[Int] = []
    var depths: List[Int] = []
    var anchor_stack: List[List[String]] = []
    var item_stack: List[List[YamlValue]] = []
    var entry_stack: List[Map[String, YamlValue]] = []
    var explicit_stack: List[Set[String]] = []
    var name_stack: List[String] = []
    var quoted_stack: List[Bool] = []

    # kind 0 is the request itself, before any container opens.
    var kind = 0
    var level = depth
    var anchors: List[String] = []
    var items: List[YamlValue] = []
    var entries = Map[String, YamlValue]()
    var explicit = Set[String]()
    var name = ""
    var quoted_key = false
    var phase = 0
    var done = YamlValue.Null
    var child_key = key

    # Phase 0 begins a value inside the innermost container, phase 1 hands it a finished value,
    # and phase 2 reads what follows the opening bracket or a comma.
    while true:
        if phase == 0:
            let child_depth = if kind == 0: depth else: level + 1

            var written: List[String] = []
            var is_key = child_key
            child_key = false

            while true:
                flow_space(var flow)
                if not is_key:
                    try count(var flow.context, child_depth)
                if cur(flow) != 38: break

                advance(var flow)

                let anchor = try anchor_name(var flow)
                flow.context.values -= 1
                written.append(anchor)
                is_key = false

            let c = cur(flow)

            if c == 91 or c == 123:
                flow.delimited = true
                if is_key: return error(
                    YamlError.UnsupportedFeature(
                        line: flow.line, reason: "complex mapping keys are unsupported"
                    )
                )

                advance(var flow)
                flow_space(var flow)
                kinds.append(kind)
                depths.append(level)
                anchor_stack.append(anchors)
                item_stack.append(items)
                entry_stack.append(entries)
                explicit_stack.append(explicit)
                name_stack.append(name)
                quoted_stack.append(quoted_key)

                kind = if c == 91: 1 else: 2

                level = child_depth
                anchors = written
                items = []
                entries = Map[String, YamlValue]()
                explicit = Set[String]()
                name = ""
                quoted_key = false
                phase = 2
                continue

            let leaf = try flow_leaf(var flow, c, is_key)
            for anchor in written.reversed():
                define_anchor(var flow.context, anchor, leaf.clone())
            done = leaf
            phase = 1
            continue

        if phase == 1:
            if kind == 0: return ok(done)

            if kind == 1:
                items.append(done)
                done = YamlValue.Null
                flow_space(var flow)

                if cur(flow) != 93:
                    if step(var flow) != 44: return error(
                        flow_invalid(
                            flow, "expected sequence comma"
                        )
                    )

                    flow_space(var flow)
                    phase = 2
                    continue
            else:
                try flow_entry(
                    var flow, name, quoted_key, var entries, var explicit, done
                )
                done = YamlValue.Null
                flow_space(var flow)

                if cur(flow) != 125:
                    if step(var flow) != 44: return error(
                        flow_invalid(
                            flow, "expected mapping comma"
                        )
                    )

                    flow_space(var flow)
                    phase = 2
                    continue

        # Phase 2 may close the container too; both end here with the closing bracket at the cursor.
        if phase == 2:
            if kind == 1:
                if cur(flow) != 93:
                    if cur(flow) == 0 or cur(flow) == 44: return error(
                        flow_invalid(
                            flow, "expected flow sequence value"
                        )
                    )

                    phase = 0
                    continue
            else if cur(flow) != 125:
                if cur(flow) == 0: return error(
                    flow_invalid(flow, "unterminated flow mapping")
                )

                quoted_key = cur(flow) == 34 or cur(flow) == 39

                let parsed_key = try flow_value(var flow, level, key: true)

                match parsed_key:
                    StringValue(text): name = text
                    _: return error(
                        YamlError.UnsupportedFeature(
                            line: flow.line, reason: "mapping keys must be strings"
                        )
                    )

                flow_space(var flow)

                # A key with no colon, as in `{a, b: 1}`, maps to null.
                if cur(flow) == 44 or cur(flow) == 125:
                    try count(var flow.context, level + 1)
                    done = YamlValue.Null
                    phase = 1
                    continue

                if step(var flow) != 58: return error(
                    flow_invalid(flow, "expected mapping colon")
                )

                phase = 0
                continue

        # The closing bracket is at the cursor: the innermost container is complete.
        advance(var flow)

        if kind == 1: done = YamlValue.ArrayValue(items)
        else: done = YamlValue.ObjectValue(entries)

        for anchor in anchors.reversed():
            define_anchor(var flow.context, anchor, done.clone())
        kind = kinds.pop().get(0)
        level = depths.pop().get(0)
        anchors = anchor_stack.pop().get([])
        items = item_stack.pop().get([])
        entries = entry_stack.pop().get(Map[String, YamlValue]())
        explicit = explicit_stack.pop().get(Set[String]())
        name = name_stack.pop().get("")
        quoted_key = quoted_stack.pop().get(false)
        phase = 1

# A plain scalar cannot start with a reserved indicator, nor with `-` or `?` followed by a space or the end.
fn plain_may_start(text: String) Bool:
    let first = text.scalar_at(0, default: 0)
    if first == 0: return true
    if (
        first == 93
        or first == 125
        or first == 44
        or first == 37
        or first == 64
        or first == 96
    ): return false

    if first == 45 or first == 63:
        let second = text.scalar_at(1, default: 0)
        return not (second == 0 or second == 32 or second == 9)

    return true

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
        let rest = text.slice_scalars(offset, text.scalar_length()).get("")
        let found = rest.index_of(marker).get(-1)
        if found < 0: return -1

        let at = offset + found
        let before = text.get(at - 1, default: "")
        let after = text.get(at + 1, default: "")
        if colon and (after == "" or after == " " or after == "\t"): return at
        if not colon and (at == 0 or before == " " or before == "\t"): return at

        offset = at + 1

# Find a mapping colon or comment outside quoted/flow values.
fn boundary(text: String, colon: Bool) Int:
    # Without the marker nothing can match; without quotes or brackets the first candidate decides.
    if colon and not text.contains(":"): return -1
    if not colon and not text.contains("#"): return -1
    if not quoted_or_nested(text): return plain_boundary(text, colon)

    # The first candidate also decides when no quote or bracket precedes it.
    let first = plain_boundary(text, colon)
    if first < 0: return -1
    if not quoted_or_nested(text.slice_scalars(0, first).get("")): return first

    let chars = text.split("")
    var quote = ""
    var depth = 0
    var index = 0

    while index < chars.length():
        let c = chars.get(index)

        if quote != "":
            if c == "\\" and quote == "\"": index += 1
            else if c == quote:
                if quote == "'" and chars.get(index + 1, default: "") == "'": index = (
                    index
                    + 1
                )
                else: quote = ""
        else if (
            (c == "\"" or c == "'")
            and (
                index == 0
                or " \t\n:[\{,".contains((chars.get((index - 1))))
            )
        ): quote = c.clone()
        else if c == "[" or c == "\{": depth += 1
        else if c == "]" or c == "\}": depth -= 1
        else if (
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
        else if (
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

fn uncomment(text: String) String:
    let index = boundary(text, colon: false)

    if index < 0:
        if not (text.ends_with(" ") or text.ends_with("\t")): return text.clone()
        if not complete(text): return text.clone()

        return blank_trim_end(text).clone()

    return blank_trim_end(text.slice(0, index).get("")).clone()

fn indent(text: String) Int:
    var result = 0
    while text.scalar_at(result, default: 0) == 32: result += 1
    return result

fn indentation(context: Context, text: String) Int!YamlError:
    let spaces = indent(text)
    if text.get(spaces, default: "") == "\t": return error(
        invalid(context, "tabs cannot indent YAML")
    )

    return ok(spaces)

# Fills the per-line facts for `context.lines` from the bytes of the document they were split from.
fn classify(var context: Context, data: Bytes) Unit:
    context.simple = []
    context.blank = []
    context.dash = []
    context.ind = []
    context.col = []

    let total = data.length()
    var pos = 0

    while context.simple.length() < context.lines.length():
        let end = data.index_of_byte(10, pos).get(total)
        var at = pos
        while at < end and data.get(at) == 32: at += 1

        let indent_width = at - pos
        var simple = at < end
        var dash = false
        var colon = -1

        if simple:
            let lead = data.get(at)
            dash = lead == 45 and (at + 1 == end or data.get(at + 1) == 32)
            if lead == 63: simple = false

        while simple and at < end:
            let b = data.get(at)

            if (
                b < 32
                or b >= 127
                or b == 35
                or b == 34
                or b == 39
                or b == 91
                or b == 93
                or b == 123
                or b == 125
            ): simple = false
            else if b == 58 and colon < 0 and (at + 1 == end or data.get(at + 1) == 32): colon = (
                at
                - pos
            )

            at += 1

        if simple and data.get(end - 1) == 32: simple = false
        context.simple.append(simple)
        context.blank.append(indent_width == end - pos)
        context.dash.append(simple and dash)
        context.ind.append(indent_width)
        context.col.append(colon)
        pos = end + 1

fn skip(var context: Context) Unit:
    while context.index < context.lines.length():
        if context.blank.get(context.index):
            context.index += 1
            continue

        if context.simple.get(context.index): break

        let line = blank_trim_start(context.lines.get(context.index))
        if line != "" and not line.starts_with("#"): break

        context.index += 1

# A document start or end marker at column zero ends a plain scalar that would otherwise continue.
fn document_marker(text: String) Bool:
    let first = text.scalar_at(0, default: 0)
    if first != 45 and first != 46: return false

    return (
        text == "---"
        or text.starts_with("--- ")
        or text == "..."
        or text.starts_with("... ")
    )

fn sequence(text: String) Bool:
    if text.scalar_at(0, default: 0) != 45: return false

    return (text == "-" or text.starts_with("- ") or text.starts_with("-\t"))

# A flow collection or quoted scalar can continue across physical lines.
fn complete(text: String) Bool:
    if not quoted_or_nested(text): return true

    var quote = ""
    var depth = 0
    var index = 0
    let chars = text.split("")

    while index < chars.length():
        let c = chars.get(index)

        if quote != "":
            if c == "\\" and quote == "\"": index += 1
            else if c == quote:
                if quote == "'" and chars.get(index + 1, default: "") == "'": index = (
                    index
                    + 1
                )
                else: quote = ""
        else if (
            (c == "\"" or c == "'")
            and (
                index == 0
                or " \t\n:[\{,".contains((chars.get((index - 1))))
            )
        ): quote = c.clone()
        else if c == "[" or c == "\{": depth += 1
        else if c == "]" or c == "\}": depth -= 1

        index += 1

    return quote == "" and depth <= 0

# Whether a value starting with this scalar is a flow collection, quote, anchor, alias or tag
# (or, with `blank`, whitespace) rather than a plain scalar.
fn structured_lead(code: Int, blank: Bool = false) Bool:
    if blank and (code == 32 or code == 9 or code == 10): return true

    return (
        code == 91
        or code == 39
        or code == 34
        or code == 123
        or code == 42
        or code == 38
        or code == 33
    )

fn inline_value(var context: Context, text: String, depth: Int) Result[
    YamlValue, YamlError
]:
    # A plain scalar needs no character scan: only its trimmed text and a count.
    if (
        text != ""
        and not structured_lead(text.scalar_at(0, default: 0), blank: true)
        and not text.contains(": ")
        and plain_may_start(blank_trim(text))
    ):
        try count(var context, depth)
        return ok(plain(blank_trim(text).clone()))

    var joined = text.clone()
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
        let next = context.lines.get(context.index)

        # Keep quote state and physical empty lines when removing comments.
        let combined = joined.concat("\n").concat(next)
        let comment = boundary(combined, colon: false)

        if comment < 0: joined = combined
        else: joined = combined.slice(0, comment).get("")

        context.index += 1

    # A flow value needs only the limits, counters and anchors, so it gets a context without
    # the document lines (copying them for every value made parsing quadratic).
    var flow = Flow(
        chars: joined.split(""),
        codes: joined.scalar_values(),
        pos: 0,
        line: line,
        context: Context(
            lines: [], final_break: context.final_break, index: context.index,
            limits: context.limits, values: context.values,
            anchors: context.anchors.clone(), sizes: context.sizes.clone(), simple: [],
            blank: [], dash: [], ind: [], col: []
        ),
        delimited: false
    )
    let result = try flow_value(var flow, depth, key: false)
    flow_space(var flow)
    if cur(flow) != 0: return error(flow_invalid(flow, "unexpected trailing text"))

    context.values = flow.context.values
    context.anchors = flow.context.anchors.clone()
    context.sizes = flow.context.sizes.clone()
    return ok(result)

fn block_string(var context: Context, header: String, base: Int) Result[
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

    for c in header.slice(1, header.scalar_length()).get("").split(""):
        offset += 1

        if (c == "+" or c == "-") and mode == "": mode = c
        else if "123456789".contains(c) and explicit == 0: explicit = (
            c
            .parse_int()
            .get()
        )
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
    var content = false

    while index < parts.length():
        let part = parts.get(index)
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

    var result = builder.build()

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
        result = result.slice(0, (result.scalar_length() - trailing)).get("")
        if (mode != "-" and content and final_break): result = result.concat("\n")

    return ok(YamlValue.StringValue(result))

# Whether a plain scalar may continue on a following line: false when the next non-blank line is
# already known to sit at or left of `base`.
fn may_continue(context: Context, base: Int) Bool:
    let first = context.index
    var probe = first

    while probe < context.lines.length():
        if context.blank.get(probe):
            probe += 1
            continue

        return not (context.simple.get(probe) and context.ind.get(probe) <= base)

    return false

fn block_value(
    var context: Context, text: String, base: Int, depth: Int, indentless: Bool
) YamlValue!YamlError:
    var remainder = blank_trim_start(text).clone()
    var anchor = ""
    var lead = remainder.scalar_at(0, default: 0)

    if lead == 38:
        var flow = Flow(
            chars: remainder.split(""), codes: [], pos: 1, line: context.index,
            context: context.clone(), delimited: false
        )
        anchor = try anchor_name(var flow)
        remainder = blank_trim_start(
            remainder.slice(flow.pos, remainder.scalar_length()).get("")
        )
        lead = remainder.scalar_at(0, default: 0)

    var result = YamlValue.Null

    if lead == 124 or lead == 62:
        try count(var context, depth)
        result = try block_string(var context, blank_trim_end(remainder), base)
    else if remainder != "":
        if not structured_lead(lead):
            remainder = blank_trim_end(remainder).clone()

            if may_continue(context, base):
                var joined = StringBuilder()
                joined.append(remainder)

                let scan_start = context.index
                var probe = scan_start
                var blanks = 0

                while probe < context.lines.length():
                    let line = context.lines.get(probe)

                    if blank_trim(line) == "":
                        blanks += 1
                        probe += 1
                        continue

                    let next = uncomment(line.clone())
                    if (
                        blank_trim(next) == ""
                        or indent(next) <= base
                        or document_marker(next)
                    ): break

                    context.index = probe

                    let _indent = try indentation(context, next)
                    if (
                        boundary(next, colon: true) >= 0
                        or sequence(blank_trim_start(next))
                    ): return error(invalid(context, "unexpected indented collection"))

                    var separator = " "

                    if blanks > 0:
                        separator = ""

                        while blanks > 0:
                            separator = separator.concat("\n")
                            blanks -= 1

                    joined.append(separator)
                    joined.append(blank_trim(next))
                    probe += 1
                    context.index = probe

                remainder = joined.build()

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
                    and sequence(blank_trim_start(line))
                )
            ):
                result = try block(var context, next_indent, depth)
            else:
                try count(var context, depth)
        else:
            try count(var context, depth)

    if anchor != "": define_anchor(var context, anchor, result.clone())
    return ok(result)

fn pad(width: Int) String:
    var builder = StringBuilder()
    var spaces = width

    while spaces > 0:
        builder.append(" ")
        spaces -= 1

    return builder.build()

# Columns of the nested sequence levels opened by consecutive compact `- ` indicators.
fn nested_columns(line: String, base: Int) List[Int]:
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

fn sequence_items(
    var context: Context, var values: List[YamlValue], base: Int, depth: Int
) Unit!YamlError:
    while context.index < context.lines.length():
        skip(var context)
        if context.index >= context.lines.length(): break

        let fast = context.simple.get(context.index)
        var line = ""
        var line_indent = 0
        var item = ""
        var compact = false

        if fast:
            line_indent = context.ind.get(context.index)
            if line_indent != base or not context.dash.get(context.index): break

            line = context.lines.get(context.index).clone()
            item = blank_trim_start(
                line.slice(line_indent + 1, line.scalar_length()).get(
                    ""
                )
            )
            compact = context.col.get(context.index) >= 0 or sequence(item)
        else:
            line = uncomment(context.lines.get(context.index))
            line_indent = try indentation(context, line)
            if line_indent < base: break
            if line_indent != base or not sequence(blank_trim_start(line)): break

            item = blank_trim_start(
                blank_trim_start(line).slice(
                    1, (blank_trim_start(line).scalar_length())
                ).get("")
            )
            compact = sequence(item) or boundary(item, colon: true) >= 0

        var chain: List[Int] = []
        if item.starts_with("-"): chain = nested_columns(line, base)

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

            context.simple.set(context.index, false)
            context.lines.set(
                context.index,
                pad(innermost).concat(
                    (
                        line
                        .slice(innermost, line.scalar_length())
                        .get("")
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
        else if compact:
            # Treat a compact mapping/sequence as a virtual indented first line.
            # Its column follows the indicator, so extra spaces move the nested base.
            let marker = blank_trim_start(line).slice(
                1, (blank_trim_start(line).scalar_length())
            ).get("")
            var gap = indent(marker)
            if gap == 0: gap = 1

            let column = base + 1 + gap

            if fast:
                let shift = column - (line.scalar_length() - item.scalar_length())
                if context.col.get(context.index) >= 0: context.col.set(
                    context.index, context.col.get(context.index) + shift
                )
                context.ind.set(context.index, column)
                context.dash.set(context.index, sequence(item))
                if item.scalar_at(0, default: 0) == 63: context.simple.set(
                    context.index, false
                )

            context.lines.set(context.index, pad(column).concat(item))
            values.append(try block(var context, column, (depth + 1)))
        else:
            context.index += 1
            values.append(
                try block_value(
                    context: var context, text: item, base: base, depth: (depth + 1),
                    indentless: false
                )
            )

    return ok(unit)

fn block(var context: Context, base: Int, depth: Int) YamlValue!YamlError:
    skip(var context)

    var first = ""
    var is_sequence = false
    var has_colon = false

    if context.simple.get(context.index):
        is_sequence = context.dash.get(context.index)
        has_colon = not is_sequence and context.col.get(context.index) >= 0
    else:
        first = blank_trim_start(uncomment(context.lines.get(context.index)))
        if first.starts_with("?") and not plain_may_start(first): return error(
            YamlError.UnsupportedFeature(
                line: (context.index + 1),
                reason: "explicit mapping keys are unsupported"
            )
        )

        is_sequence = sequence(first)
        has_colon = not is_sequence and boundary(first, colon: true) >= 0

    if is_sequence:
        try count(var context, depth)

        var values: List[YamlValue] = []
        try sequence_items(
            context: var context, values: var values, base: base, depth: depth
        )
        return ok(YamlValue.ArrayValue(values))

    if has_colon:
        try count(var context, depth)

        var values = Map[String, YamlValue]()
        var explicit = Set[String]()

        while context.index < context.lines.length():
            skip(var context)
            if context.index >= context.lines.length(): break

            var line_indent = 0
            var name = ""
            var text = ""

            if context.simple.get(context.index):
                line_indent = context.ind.get(context.index)
                if line_indent != base or context.dash.get(context.index): break

                let colon = context.col.get(context.index)
                if colon < 0: break

                let raw = context.lines.get(context.index)
                name = blank_trim(raw.slice(line_indent, colon).get(""))
                text = blank_trim_start(
                    raw.slice(colon + 1, raw.scalar_length()).get(
                        ""
                    )
                )
            else:
                let line = uncomment(context.lines.get(context.index))
                line_indent = try indentation(context, line)
                if line_indent != base or sequence(blank_trim_start(line)): break

                let content = blank_trim_start(line)
                let colon = boundary(content, colon: true)
                if colon < 0: break

                name = blank_trim(content.slice(0, colon).get(""))
                text = blank_trim_start(
                    content.slice(
                        colon + 1, content.scalar_length()
                    ).get("")
                )

            let key_start = name.scalar_at(0, default: 0)
            let quoted_key = key_start == 34 or key_start == 39

            if quoted_key:
                var flow = Flow(
                    chars: name.split(""), codes: [], pos: 0, line: (context.index + 1),
                    context: context.clone(), delimited: false
                )
                name = try quoted(var flow)
                if flow.pos != flow.chars.length(): return error(
                    invalid(context, "invalid quoted key")
                )
            else if (
                name == ""
                or key_start == 91
                or key_start == 123
                or key_start == 33
                or key_start == 38
                or key_start == 42
            ):
                return error(
                    YamlError.UnsupportedFeature(
                        line: context.index + 1, reason: "mapping keys must be strings"
                    )
                )

            if (
                not quoted_key
                and (
                    not plain_may_start(name)
                    or key_start == 124
                    or key_start == 62
                )
            ): return error(
                invalid(
                    context,
                    "a plain mapping key cannot start with an indicator character"
                )
            )
            if explicit.contains(name): return error(
                invalid(context, "duplicate mapping key")
            )

            explicit.add(name.clone())

            let key_line = context.index + 1
            context.index += 1

            let value = try block_value(
                context: var context, text: text, base: base, depth: (depth + 1),
                indentless: true
            )

            if name == "<<" and not quoted_key:
                try merge(
                    line: key_line, column: line_indent + 1, target: var values,
                    value: value
                )
            else:
                values.add(name, value)

        return ok(YamlValue.ObjectValue(values))

    if first == "": first = blank_trim_start(context.lines.get(context.index))
    context.index += 1
    return block_value(
        context: var context,
        text: first,
        # A scalar or anchor on its own line may continue at the same indentation.
        base: base - 1,
        depth: depth,
        indentless: false
    )

fn validate(var context: Context, value: YamlValue, depth: Int) Unit!YamlError:
    try count(var context, depth)

    match value:
        ArrayValue(values):
            for item in values: try validate(var context, item, (depth + 1))
        ObjectValue(values):
            for entry in values: try validate(var context, entry.value, (depth + 1))
        _: unit

    return ok(unit)

# Parses a YAML document. Unsupported YAML features and invalid input include source locations.
export fn parse(text: String, limits: YamlLimits?) YamlValue!YamlError:
    var options = default_limits()
    if let value = limits:
        options = value
    for limit in [options.max_bytes, options.max_depth, options.max_values]:
        if let value = limit:
            if value < 0: return error(YamlError.InvalidInput)
    if not within(text.byte_length(), options.max_bytes): return error(
        YamlError.LimitExceeded
    )

    var normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    if normalized.starts_with("\u{feff}"): normalized = normalized.slice(
        1, normalized.scalar_length()
    ).get("")
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
        sizes: Map[String, Int](), simple: [], blank: [], dash: [], ind: [], col: []
    )

    # split's synthetic terminal empty line is not scalar content.
    if normalized.ends_with("\n"): context.lines.remove(context.lines.length() - 1)
    classify(var context, normalized.to_bytes())
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

        if not blank_trim(rest).starts_with("#"):
            context.lines.splice(context.index, 1, ["---", rest])
            classify(var context, context.lines.join("\n").to_bytes())

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

    # Without aliases, parsing already counted every container and leaf at its depth.
    if context.values > 0 and context.anchors.length() == 0: return ok(result)

    context.values = 0
    try validate(var context, result, 1)
    return ok(result)

fn hex4(code: Int) String:
    var digits = code.to_string_radix(16)
    while digits.length() < 4: digits = "0".concat(digits)
    return digits

fn quote_text(text: String) String:
    var clean = true

    for code in text.scalar_values():
        if code < 32 or code == 34 or code == 92 or (code >= 127 and code <= 159):
            clean = false
            break

    if clean: return "\"".concat(text).concat("\"")

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
        else if code < 32 or (code >= 127 and code <= 159):
            result.append("\\u")
            result.append(hex4(code))
        else: result.append(c)

    result.append("\"")
    return result.build()

fn format_key(key: String) String:
    var plain = key != ""
    var first = true

    for code in key.scalar_values():
        let word = (
            (code >= 97 and code <= 122)
            or (code >= 65 and code <= 90)
            or code == 95
        )
        let digit = code >= 48 and code <= 57
        if not (word or digit or code == 45): plain = false
        if first and (digit or code == 45): plain = false
        first = false
        if not plain: break

    if plain and key.length() <= 5:
        if ["null", "true", "false", "yes", "no", "on", "off", "y", "n"].contains(
            key.lower()
        ): plain = false
    if plain: return key

    return quote_text(key)

# A number keeps its original token, so it must resolve back to a number.
fn valid_number(text: String) Bool:
    # Plain decimal integers resolve to themselves; anything else goes through the parser.
    var integer = text != ""
    var at = 0

    for code in text.scalar_values():
        if not (code >= 48 and code <= 57 or (at == 0 and (code == 45 or code == 43))):
            integer = false
            break

        at += 1

    if integer and at > 1 or (integer and text.scalar_at(0) >= 48): return true
    if let parsed = parse(text): return parsed == YamlValue.NumberValue(text)

    return false

fn scalar_text(value: YamlValue) String!YamlError:
    match value:
        Null: return ok("null")
        BoolValue(flag): return ok(flag.to_string())
        StringValue(text): return ok(quote_text(text))
        NumberValue(text):
            if not valid_number(text.clone()): return error(YamlError.InvalidInput)

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

fn emit_block(var out: StringBuilder, value: YamlValue, indent: String) Result[
    Unit, YamlError
]:
    match value:
        ArrayValue(values):
            for item in values:
                out.append(indent)

                if is_block(item):
                    out.append("-\n")
                    try emit_block(var out, item, indent.concat("  "))
                else:
                    let text = try scalar_text(item.clone())
                    out.append("- ")
                    out.append(text)
                    out.append("\n")

            return ok(unit)
        ObjectValue(values):
            for entry in values.entries():
                out.append(indent)
                out.append(format_key(entry.key.clone()))

                if is_block(entry.value):
                    out.append(":\n")
                    try emit_block(var out, entry.value, indent.concat("  "))
                else:
                    let text = try scalar_text(entry.value.clone())
                    out.append(": ")
                    out.append(text)
                    out.append("\n")

            return ok(unit)
        _: return ok(unit)

# Serializes a YAML value in block style with double-quoted strings.
export fn stringify(value: YamlValue, max_bytes: Int?) String!YamlError:
    if let limit = max_bytes:
        if limit < 0: return error(YamlError.InvalidInput)

    var out = StringBuilder()

    if is_block(value.clone()): try emit_block(var out, value, "")
    else:
        let text = try scalar_text(value.clone())
        out.append(text.concat("\n"))

    let text = out.build()
    if not within(text.byte_length(), max_bytes): return error(YamlError.LimitExceeded)

    return ok(text)
