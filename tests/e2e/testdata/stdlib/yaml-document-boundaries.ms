import parse, YamlValue from "@std/data/yaml.ms"
import expect_equal from "@std/test/test.ms"

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
