// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

type Label:
	text: String
	parts: List[String]

fn Label.name() String:
	return self.text

fn Label.first() String:
	return self.parts[0]

fn Label.greeting(prefix: String = "hi") String:
	return self.text

test "a temporary receiver returns its borrowed string":
	name := Label("example", ["a"]).name
	expect_equal(name(), "example")?

test "a named receiver returns its borrowed string":
	label := Label("named", ["b"])
	name := label.name
	expect_equal(name(), "named")?
	expect_equal(label.text, "named")?

test "a borrowed list element is copied for each call":
	label := Label("x", ["elem"])
	first := label.first
	expect_equal(first(), "elem")?
	expect_equal(first(), "elem")?

test "a method with a default keeps its borrowed result":
	label := Label("dflt", ["c"])
	greeting := label.greeting
	expect_equal(greeting(), "dflt")?
	expect_equal(greeting("yo"), "dflt")?
