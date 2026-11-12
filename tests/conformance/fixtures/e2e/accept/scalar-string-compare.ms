// conform: tags=strings,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn classify(text: String) Int:
	var n = 0
	var i = 0

	while i < text.length():
		c := text.get(i)

		if c == "é":
			n += 100
		else if c >= "a" and c <= "z":
			n += 1
		else if "0" < c:
			n += 10

		i += 1

	return n

fn echo(text: String) String:
	c := text.get(0)
	if c == "x": return c

	return c + "!"

fn not_a(text: String) Int:
	var n = 0
	for c in text.chars():
		if c != "a":
			n += 1
	return n

fn keep(text: String) List[String]:
	var out: List[String] = []
	for c in text.chars():
		if c == "b":
			out.append(c)
	return out

test "get compared with one-character literals":
	classify("abé9 Z") | expect_equal(122)?
	("aé".get(-1) == "é") | expect_equal(true)?
	("€".get(0) > "z") | expect_equal(true)?
	("a".get(0) <= "a") | expect_equal(true)?

test "a name that is also used as a String stays a String":
	echo("xy") | expect_equal("x")?
	echo("yz") | expect_equal("y!")?

test "chars elements compared and kept":
	not_a("aéb") | expect_equal(2)?
	keep("abcb") | expect_equal(["b", "b"])?

fn digits(text: String) Int:
	var n = 0
	var i = 0

	while i < text.length():
		c := text.get(i)
		n = n * 10 + c.parse_int().get(0)
		i += 1

	return n

fn both(text: String) Int:
	c := text.get(0)
	if c == "7": return c.parse_int().get(-1) + c.length()

	return -1

test "parse_int of a one-character string":
	digits("4096") | expect_equal(4096)?
	digits("1a2") | expect_equal(102)?
	digits("é+") | expect_equal(0)?
	both("7") | expect_equal(8)?
	"x5".get(1).parse_int() | expect_equal(5)?
