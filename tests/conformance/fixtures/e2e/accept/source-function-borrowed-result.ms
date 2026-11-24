// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn identity(s String) String:
	return s

fn apply(f fn(String) String, s String) String:
	return f(s)

test "borrowed string callback":
	s := "hello"
	out := apply(text => identity(text).clone(), s)
	expect_equal(out, "hello")?

fn generic[T](value T) T:
	return value

fn pick(items List[String]) String:
	return items[0]

test "generic and list-field callback results outlive arguments":
	generic_string fn(String) String := text => generic[String](text).clone()
	first := generic_string(f"dynamic-{42}")
	picker fn(List[String]) String := items => pick(items).clone()
	second := picker([f"dynamic-{17}"])
	expect_equal(first, "dynamic-42")?
	expect_equal(second, "dynamic-17")?

fn default_identity(value String, _tag Int = 0) String:
	return value

test "defaulted source callback preserves borrowed strings":
	f fn(String, Int) String := (text, tag) => default_identity(text, tag).clone()
	first := f(f"default-{1}", 0)
	second := f(f"explicit-{2}", 3)
	expect_equal(first, "default-1")?
	expect_equal(second, "explicit-2")?

fn list_identity(items List[String]) List[String]:
	return items

test "borrowed list callback returns independent data":
	f fn(List[String]) List[String] := items => list_identity(items).clone()
	first := f([f"a-{1}", f"b-{2}"])
	second := f([f"c-{3}"])
	expect_equal(first, ["a-1", "b-2"])?
	expect_equal(second, ["c-3"])?
