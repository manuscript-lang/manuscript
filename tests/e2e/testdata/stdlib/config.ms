import expect_equal, expect_ok, fail from "@std/test/test.ms"
import parse_dotenv, parse_ini, ConfigError from "@std/data/config.ms"

test "dotenv reads names, quotes, comments and export":
    let text = "# settings\nPORT=8080\nexport HOST = example.com # primary\nNAME='my # app'\nTITLE=\"two\nlines\" # note\nEMPTY=\nTICK=`a b`\n"
    let values = (parse_dotenv(text) | try expect_ok)
    values.keys() | try expect_equal(["PORT", "HOST", "NAME", "TITLE", "EMPTY", "TICK"])
    values.get("PORT").get("") | try expect_equal("8080")
    values.get("HOST").get("") | try expect_equal("example.com")
    values.get("NAME").get("") | try expect_equal("my # app")
    values.get("TITLE").get("") | try expect_equal("two\nlines")
    values.get("EMPTY").get("x") | try expect_equal("")
    values.get("TICK").get("") | try expect_equal("a b")

test "dotenv later duplicates replace earlier values":
    let values = (parse_dotenv("A=1\nB=2\nA=3\n") | try expect_ok)
    values.keys() | try expect_equal(["A", "B"])
    values.get("A").get("") | try expect_equal("3")

test "dotenv accepts empty text and a byte-order mark":
    (parse_dotenv("") | try expect_ok).length() | try expect_equal(0)
    (parse_dotenv("\u{feff}A=1") | try expect_ok).get(
        "A"
    ).get("") | try expect_equal("1")
    (parse_dotenv("\r\nA=1\r\nB=2\r\n") | try expect_ok).get(
        "B"
    ).get("") | try expect_equal("2")

test "dotenv rejects malformed lines with their line number":
    let bad = [
        "=x", "A B=1", "1A=2", "A='open", "A='x' junk", "NOEQUALS", "export  =bad"
    ]
    for text in bad:
        if let _ = parse_dotenv(text): return fail("accepted {text}")

    let result = parse_dotenv("A=1\n\nB='x' junk\n")
    if let _ = result: return fail("accepted trailing text")

    result | try expect_equal(
        error(ConfigError.InvalidData(3, "unexpected text after quoted value"))
    )

test "ini reads sections, both separators, comments and quotes":
    let text = "top = 1\n; comment\n[db]\nhost = localhost\nport: 5432\nurl = a=b:c\n# note\n[ app ]\nname = \"x ; y\" \nmode = fast ; inline\n[db]\nuser = ann\n"
    let ini = (parse_ini(text) | try expect_ok)
    ini.keys() | try expect_equal(["", "db", "app"])
    ini.get("").get(Map[String, String]()).get("top").get("") | try expect_equal("1")

    let db = ini.get("db").get(Map[String, String]())
    db.keys() | try expect_equal(["host", "port", "url", "user"])
    db.get("port").get("") | try expect_equal("5432")
    db.get("url").get("") | try expect_equal("a=b:c")

    let app = ini.get("app").get(Map[String, String]())
    app.get("name").get("") | try expect_equal("x ; y")
    app.get("mode").get("") | try expect_equal("fast")

test "ini rejects malformed lines":
    for text in ["[open", "just words", "= value"]:
        if let _ = parse_ini(text): return fail("accepted {text}")

    let result = parse_ini("a=1\nbad")
    if let _ = result: return fail("accepted")

    result | try expect_equal(error(ConfigError.InvalidData(2, "expected key = value")))
