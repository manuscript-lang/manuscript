// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	parse_dotenv, parse_ini from "@std/data/config.ms",
	expect_equal, expect_ok, expect_true, fail from "@std/test/test.ms",
)

test "dotenv reads names, quotes, comments and export":
	text := "# settings\nPORT=8080\nexport HOST = example.com # primary\nNAME='my # app'\nTITLE=\"two\nlines\" # note\nEMPTY=\nTICK=`a b`\n"
	values := (parse_dotenv(text) | expect_ok?)
	values.keys() | expect_equal(["PORT", "HOST", "NAME", "TITLE", "EMPTY", "TICK"])?
	values.get_or("PORT", "") | expect_equal("8080")?
	values.get_or("HOST", "") | expect_equal("example.com")?
	values.get_or("NAME", "") | expect_equal("my # app")?
	values.get_or("TITLE", "") | expect_equal("two\nlines")?
	values.get_or("EMPTY", "x") | expect_equal("")?
	values.get_or("TICK", "") | expect_equal("a b")?

test "dotenv ends a bare value only at a hash that starts it or follows a space":
	values := (
		parse_dotenv(
			"A=ab#cd\nB=https://x/#top\nC=1\t# c\nD=#only\nE=x #y\n"
		) | expect_ok?
	)
	values.get_or("A", "x") | expect_equal("ab#cd")?
	values.get_or("B", "x") | expect_equal("https://x/#top")?
	values.get_or("C", "x") | expect_equal("1")?
	values.get_or("D", "x") | expect_equal("")?
	values.get_or("E", "x") | expect_equal("x")?

test "dotenv keeps spaces and tabs inside a multiline quoted value":
	text := "A=\"hello  \nworld\"\nB='x \t\ny'\nC=`z   \nw` # c\nD=  \"one  \" \n"
	values := (parse_dotenv(text) | expect_ok?)
	values.get_or("A", "") | expect_equal("hello  \nworld")?
	values.get_or("B", "") | expect_equal("x \t\ny")?
	values.get_or("C", "") | expect_equal("z   \nw")?
	values.get_or("D", "") | expect_equal("one  ")?

test "dotenv later duplicates replace earlier values":
	values := (parse_dotenv("A=1\nB=2\nA=3\n") | expect_ok?)
	values.keys() | expect_equal(["A", "B"])?
	values.get_or("A", "") | expect_equal("3")?

test "dotenv accepts empty text and a byte-order mark":
	(parse_dotenv("") | expect_ok?).length() | expect_equal(0)?
	(parse_dotenv("\u{feff}A=1") | expect_ok?).get_or("A", "") | expect_equal("1")?
	(
		(parse_dotenv("\r\nA=1\r\nB=2\r\n") | expect_ok?).get_or("B", "")
		| expect_equal("2")?
	)

test "dotenv rejects malformed lines with their line number":
	bad := ["=x", "A B=1", "1A=2", "A='open", "A='x' junk", "NOEQUALS", "export  =bad"]
	for text in bad:
		if _ := parse_dotenv(text): return fail("accepted {text}")

	result := parse_dotenv("A=1\n\nB='x' junk\n")
	if _ := result: return fail("accepted trailing text")

	(
		result | expect_equal(
			error(
				Error(
					"config: line 3: unexpected text after quoted value",
					details: {"line": "3"},
					kind: "EBADMSG",
				)
			)
		)?
	)

test "ini reads sections, both separators, comments and quotes":
	text := "top = 1\n; comment\n[db]\nhost = localhost\nport: 5432\nurl = a=b:c\n# note\n[ app ]\nname = \"x ; y\" \nmode = fast ; inline\n[db]\nuser = ann\n"
	ini := (parse_ini(text) | expect_ok?)
	ini.keys() | expect_equal(["", "db", "app"])?
	ini.get_or("", Map[String, String]()).get_or("top", "") | expect_equal("1")?

	db := ini.get_or("db", Map[String, String]())
	db.keys() | expect_equal(["host", "port", "url", "user"])?
	db.get_or("port", "") | expect_equal("5432")?
	db.get_or("url", "") | expect_equal("a=b:c")?

	app := ini.get_or("app", Map[String, String]())
	app.get_or("name", "") | expect_equal("x ; y")?
	app.get_or("mode", "") | expect_equal("fast")?

test "ini rejects malformed lines":
	for text in ["[open", "just words", "= value"]:
		if _ := parse_ini(text): return fail("accepted {text}")

	result := parse_ini("a=1\nbad")
	if _ := result: return fail("accepted")

	(
		result | expect_equal(
			error(
				Error(
					"config: line 2: expected key = value",
					details: {"line": "2"},
					kind: "EBADMSG",
				)
			)
		)?
	)

test "dotenv multi-line quotes stay linear":
	lines := "x\n".repeat(200000).get()
	values := (parse_dotenv("A=\"{lines}end\" # c\nB=1") | expect_ok?)
	values.get_or("B", "") | expect_equal("1")?
	values.get_or("A", "").scalar_length() | expect_equal(400003)?
	expect_true(parse_dotenv("A=\"{lines}").is_error())?

test "ini detects comments before trimming empty assignment values":
	for separator in ["=", ":"]:
		for marker in ["#", ";"]:
			text := "empty{separator} {marker} optional\n[設定]\nkey{separator}old\nkey{separator}   {marker} replaced\nplain{separator}\n"
			ini := parse_ini(text)?
			ini.get("").get().get("empty").get() | expect_equal("")?

			section := ini.get("設定").get()
			section.keys() | expect_equal(["key", "plain"])?
			section.get("key").get() | expect_equal("")?
			section.get("plain").get() | expect_equal("")?

test "ini preserves literal markers and quoted whitespace":
	ini := parse_ini(
		"hash=#literal\nsemi:;literal\ntab=\t#literal\ninner=x\t;literal\nquoted=  \" # text ; 界 \"  \nsingle:  ' ; text # é '  \nempty= \"\"\n"
	)?
	values := ini.get("").get()
	values.get("hash").get() | expect_equal("#literal")?
	values.get("semi").get() | expect_equal(";literal")?
	values.get("tab").get() | expect_equal("#literal")?
	values.get("inner").get() | expect_equal("x\t;literal")?
	values.get("quoted").get() | expect_equal(" # text ; 界 ")?
	values.get("single").get() | expect_equal(" ; text # é ")?
	values.get("empty").get() | expect_equal("")?

test "dotenv keeps CRLF inside a quoted value and accepts CRLF records":
	values := (
		parse_dotenv(
			"A=\"one\r\ntwo\"\r\nB=3\r\nC='x\r\n\r\ny' # c\r\nD=\"z\"\r\n"
		) | expect_ok?
	)
	expect_equal(values.get("A").get(""), "one\r\ntwo")?
	expect_equal(values.get("B").get(""), "3")?
	expect_equal(values.get("C").get(""), "x\r\n\r\ny")?
	expect_equal(values.get("D").get(""), "z")?

	mixed := (parse_dotenv("A=\"a\nb\r\nc\"\nB=1") | expect_ok?)
	expect_equal(mixed.get("A").get(""), "a\nb\r\nc")?

test "INI comments follow quoted values":
	ini := (
		parse_ini(
			"a = \"x # y\" # comment\nb = 'p ; q' ; note\nc = \"plain\" # n\nd = \"k\"#tight\ne = \"q\"\nf = \"w\" tail\""
		)
		| expect_ok?
	)
	top := ini.get("").get(Map[String, String]())
	expect_equal(top.get("a").get(""), "x # y")?
	expect_equal(top.get("b").get(""), "p ; q")?
	expect_equal(top.get("c").get(""), "plain")?
	expect_equal(top.get("d").get(""), "\"k\"#tight")?
	expect_equal(top.get("e").get(""), "q")?
	expect_equal(top.get("f").get(""), "w\" tail")?

test "INI comments after quotes may contain the quote and ignore tab-only markers":
	ini := (
		parse_ini(
			"a=\"x\" # note \"\nb='y' ; it's\nc=\"z\"  ;   \"q\"\nd=\"x\"\t#literal\ne='t'\t;literal"
		)
		| expect_ok?
	)
	top := ini.get("").get(Map[String, String]())
	expect_equal(top.get("a").get(""), "x")?
	expect_equal(top.get("b").get(""), "y")?
	expect_equal(top.get("c").get(""), "z")?
	expect_equal(top.get("d").get(""), "\"x\"\t#literal")?
	expect_equal(top.get("e").get(""), "'t'\t;literal")?
