import parse, YamlValue from "@std/data/yaml.ms"
import expect_equal, expect_error from "@std/test/test.ms"

test "same-line document content cannot be a block collection":
    for body in [
        "value: word", "- word", "-", "\"key\": word", "&name value: word",
        "  value: word", "  - word"
    ]:
        try expect_equal(parse("--- {body}\n").is_error(), true)
        try expect_equal(parse("%YAML 1.2\n--- {body}\n").is_error(), true)

test "inline flow and scalar document content stays supported":
    for body in ["word", "\"word\"", "'word'", "&name word"]:
        try expect_equal((try parse("--- {body}\n")), YamlValue.StringValue("word"))
    try expect_equal(
        (try parse("--- \"value: word\"\n")), YamlValue.StringValue("value: word")
    )
    try expect_equal((try parse("--- \"- word\"\n")), YamlValue.StringValue("- word"))
    try expect_equal((try parse("--- \{value: word\}\n")), (try parse("value: word\n")))
    try expect_equal((try parse("--- [word]\n")), (try parse("- word\n")))
    try expect_equal((try parse("--- |\n  word\n")), YamlValue.StringValue("word\n"))

test "anchored inline flow collection stays supported":
    try expect_equal(
        (try parse("--- &name \{value: word\}\n")), (try parse("value: word\n"))
    )

test "block collections following the physical marker line stay supported":
    for prefix in ["---\n", "--- # comment\n", "--- &name\n", "%YAML 1.2\n--- &name\n"]:
        try expect_equal(
            (try parse("{prefix}value: word\n")), (try parse("value: word\n"))
        )
        try expect_equal((try parse("{prefix}- word\n")), (try parse("- word\n")))

test "same-line block collection errors retain physical locations":
    let first = parse("--- value: word\n")
    try expect_equal(first.is_error(), true)
    try expect_equal(first.err().details.get("line"), "1")
    try expect_equal(first.err().details.get("column"), "5")

    let second = parse("%YAML 1.2\n--- - word\n")
    try expect_equal(second.is_error(), true)
    try expect_equal(second.err().details.get("line"), "2")
    try expect_equal(second.err().details.get("column"), "5")

test "document markers cannot continue flow collections or quoted scalars":
    for marker in ["---", "..."]:
        for suffix in ["", " ", " # boundary", "\t# boundary"]:
            for prefix in ["[", "[word,", "\{key:", "\"word", "'word"]:
                let closing = if prefix == "'word": "'" else if prefix == "\"word": "\"" else if prefix == "\{key:": "\}" else: "]"
                let cause = parse("{prefix}\n{marker}{suffix}\n{closing}") | try expect_error
                try expect_equal(cause.kind, "EBADMSG")
                try expect_equal(cause.details["line"], "2")
                try expect_equal(cause.details["column"], "1")

test "flow document boundary errors retain physical source rows":
    for source in [
        "--- [\n# comment\n---\n]", "--- \"word\n# quoted text\n...\n\"",
        "- key: [\n# comment\n---\n]"
    ]:
        let cause = parse(source) | try expect_error
        try expect_equal(cause.kind, "EBADMSG")
        try expect_equal(cause.details["line"], "3")
        try expect_equal(cause.details["column"], "1")

test "quoted escapes and normalized line endings retain document boundaries":
    for ending in ["\n", "\r\n", "\r"]:
        for prefix in ["\"word", "\"word\\", "'word"]:
            let closing = if prefix == "'word": "'" else: "\""
            let source = "{prefix}\n---\n{closing}".replace("\n", ending)
            let cause = parse(source) | try expect_error
            try expect_equal(cause.kind, "EBADMSG")
            try expect_equal(cause.details["line"], "2")
            try expect_equal(cause.details["column"], "1")

test "tab separated document markers end plain scalar continuation":
    for marker in ["---", "..."]:
        let cause = parse("word\n{marker}\tmore\n") | try expect_error
        try expect_equal(cause.kind, "EBADMSG")
        try expect_equal(cause.details["line"], "2")

test "indented markers and marker prefixes remain scalar content":
    for marker in ["---", "..."]:
        try expect_equal(
            (try parse("[\n {marker}\n]")),
            YamlValue.ArrayValue([YamlValue.StringValue(marker.clone())])
        )
        for quote in ["'", "\""]:
            try expect_equal(
                (try parse("{quote}word\n {marker}\n end{quote}")),
                YamlValue.StringValue("word {marker} end")
            )
        for suffix in ["word", "#literal", "\u{a0}word"]:
            try expect_equal(
                (try parse("[\n{marker}{suffix}\n]")),
                YamlValue.ArrayValue(
                    [YamlValue.StringValue("{marker}{suffix}")]
                )
            )
        try expect_equal(
            (try parse("[\n{marker}]")),
            YamlValue.ArrayValue([YamlValue.StringValue(marker.clone())])
        )
