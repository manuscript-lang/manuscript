import stringify, parse, TomlValue, TomlError from "@std/toml.ms"
import expect_equal from "@std/test.ms"
import from_scalars from "@std/string.ms"

fn table(text: String) TomlValue:
    var fields = Map[String, TomlValue]()
    fields.add("value", TomlValue.StringValue(text))
    return TomlValue.TableValue(fields)

test "TOML quoting preserves empty plain and Unicode text":
    for text in [
        "", "Ada", "space punctuation : ; # ' []", "é🙂日本語", "é🙂日本語".repeat(1024).get()
    ]:
        let root = table(text.clone())
        let out = try stringify(root)
        out | try expect_equal("value = \"".concat(text).concat("\"\n"))
        (try parse(out)) | try expect_equal(root)

test "TOML quoting preserves escaped control and Unicode text":
    for text in [
        "\"", "\\", "\n", "\t", "\r", "\u{8}", "\u{c}", "\u{0}", "\u{1f}", "\u{7f}",
        "é🙂\n日本語\\", "abcdefgh".repeat(2048).get().concat("\n")
    ]:
        let root = table(text)
        (try parse(try stringify(root))) | try expect_equal(root)

    stringify(table("\"\\\n\t\r\u{8}\u{c}\u{0}\u{1f}\u{7f}")) | try expect_equal(
        ok("value = \"\\\"\\\\\\n\\t\\r\\b\\f\\u0000\\u001f\\u007f\"\n")
    )

test "TOML quoting retains exact and invalid output budgets":
    let root = table("é🙂")
    let text = try stringify(root)
    stringify(root, max_bytes: text.byte_length()) | try expect_equal(ok(text.clone()))
    stringify(root, max_bytes: text.byte_length() - 1) | try expect_equal(
        error(TomlError.LimitExceeded)
    )
    stringify(root, max_bytes: -1) | try expect_equal(error(TomlError.InvalidInput))

test "TOML quoting preserves quoted keys and all ASCII control escapes":
    for key in ["", "é🙂", "quote\"", "slash\\", "line\n", "\u{7f}"]:
        var fields = Map[String, TomlValue]()
        fields.add(key, TomlValue.IntValue(7))

        let root = TomlValue.TableValue(fields)
        (try parse(try stringify(root))) | try expect_equal(root)

    var fields = Map[String, TomlValue]()
    fields.add("é🙂", TomlValue.StringValue("plain"))
    stringify(TomlValue.TableValue(fields)) | try expect_equal(
        ok("\"é🙂\" = \"plain\"\n")
    )

    var controls = ""
    for code in 0..32:
        controls = controls.concat(from_scalars([code]).get())

    let root = table(controls)
    (try parse(try stringify(root))) | try expect_equal(root)
