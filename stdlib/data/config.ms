// Builds the error for a malformed line: `config: line <n>: <reason>`, with the line in `details`.
fn config_error(line: Int, reason: String) Error:
    return Error(
        "config: line {line}: {reason}", kind: "EBADMSG", details: {"line": "{line}"}
    )

/*
Read `.env` settings in file order without changing the environment; [load_environment](../os/process.ms.md#load_environment) loads them into the process.

- Skip blanks, BOM and comments; optional `export` precedes names made of letters/digits/underscore, never starting with a digit.
- Bare values trim whitespace and ` #` comments. Single/double/backtick quotes preserve multiline text and `#`; only trailing text may comment. Duplicates replace values without reordering keys.
*/
export fn parse_dotenv(text: String) Map[String, String]!:
    var out = Map[String, String]()
    let lines = text.cut_prefix("\u{feff}").get(text).lines()
    var index = 0

    while index < lines.length():
        let number = index + 1
        let entry = lines[index].trim()
        index += 1
        if entry.is_empty() or entry.starts_with("#"): continue

        let assignment = entry.cut_prefix("export ").get(entry)
        let found = assignment.index_of("=")
        if found.is_none(): return error(config_error(number, "expected NAME=value"))

        let at = found.get(0)
        let name = assignment.take(at).trim()
        if not valid_name(name): return error(
            config_error(number, "invalid variable name")
        )

        let value = assignment.drop(at + 1).trim()
        let quote = value.take(1)

        if quote != "'" and quote != "\"" and quote != "`":
            out.add(name, value.split("#", 2)[0].trim())
            continue

        // Only the newest line is searched for the closing quote, so a long value stays linear.
        var parts = [value.drop(1)]
        var closing = parts[0].index_of(quote)

        while closing.is_none():
            if index >= lines.length(): return error(
                config_error(number, "unterminated quote")
            )

            parts.append(lines[index].clone())
            closing = lines[index].index_of(quote)
            index += 1

        let last = parts.length() - 1
        let body = parts.join("\n")
        let end = body.scalar_length() - parts[last].scalar_length() + closing.get(0)
        let trailing = body.drop(end + 1).trim()
        if not trailing.is_empty() and not trailing.starts_with("#"): return error(
            config_error(number, "unexpected text after quoted value")
        )

        out.add(name, body.take(end))

    return ok(out)

/*
Read ordered INI sections; keys before a header belong to the empty-name section.

- Trim names/keys; repeated headers continue a section, duplicate keys replace values. The first `=` or `:` divides key from value; missing separators return `EBADMSG`.
- `#`/`;` start comment lines or inline comments after a space. Matching single/double quotes preserve comment text and are removed.
*/
export fn parse_ini(text: String) Map[String, Map[String, String]]!:
    var sections = Map[String, Map[String, String]]()
    sections.add("", Map[String, String]())

    var current = ""
    var number = 0

    for raw in text.cut_prefix("\u{feff}").get(text).lines():
        number += 1

        let entry = raw.trim()
        if entry.is_empty() or entry.starts_with("#") or entry.starts_with(";"): continue

        if entry.starts_with("["):
            if not entry.ends_with("]"): return error(
                config_error(number, "unterminated section header")
            )

            current = entry.drop(1).take(entry.length() - 2).trim()
            sections.add_default(current.clone(), Map[String, String]())
            continue

        let split = first_assignment(entry)
        if split.is_none(): return error(config_error(number, "expected key = value"))

        let at = split.get(0)
        let key = entry.take(at).trim()
        if key.is_empty(): return error(config_error(number, "empty key"))

        if var section = sections.get(current):
            section.add(key, ini_value(entry.drop(at + 1).trim()))

    return ok(sections)

fn valid_name(name: String) Bool:
    if name.is_empty(): return false

    var position = 0

    for code in name.scalar_values():
        let letter = (code >= 97 and code <= 122) or (code >= 65 and code <= 90)
        let digit = code >= 48 and code <= 57
        if not (letter or code == 95 or (digit and position > 0)): return false

        position += 1

    return true

fn first_assignment(entry: String) Int?:
    let eq = entry.index_of("=")
    let colon = entry.index_of(":")
    if eq.is_none(): return colon
    if colon.is_none(): return eq

    return eq.get(0).min(colon.get(0))

fn ini_value(value: String) String:
    let quote = value.take(1)
    if (
        value.length() >= 2
        and (quote == "\"" or quote == "'")
        and value.ends_with(quote)
    ):
        return value.drop(1).take(value.length() - 2)

    var cut = value.length()
    for marker in [" #", " ;"]:
        if let at = value.index_of(marker):
            cut = cut.min(at)
    return value.take(cut).trim()
