// conform: tags=control-flow,formatter,interpolation,lists,modules,mutation,optional,parser,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/if-let.ms
import expect_true, fail from "@std/test/test.ms"

fn describe(name: String?) String:
	value := name

	if value != null:
		return "Hello, " + value
	else:
		return "Hello!"

fn total(items: List[Int?]) Int:
	var sum = 0

	for item in items:
		value := item
		if value != null:
			sum += value

	return sum

fn check(value: Bool, message: String) Void!:
	(value) | expect_true?

test "if let unwraps a present optional":
	value := [4, 5].first()

	if value != null:
		(check(value: value == 4, message: "wrong value")?)
	else:
		fail(message: "expected some")?

test "if let takes else when absent and keeps falsy payloads":
	(check(value: describe(null) == "Hello!", message: "none")?)
	(check(value: describe("Ada") == "Hello, Ada", message: "some")?)

	items: List[Int?] := [1, null, 0, 2]
	(check(value: total(items) == 3, message: "total")?)

	empty: List[Int] := []
	value := empty.first()
	if value != null: return fail(message: f"unexpected {value}")

fn parse(text: String) Int!Error:
	if text == "": return error(Error("empty"))
	return ok(text.length())

test "if let unwraps an ok result and takes else on error":
	if value := parse("abc"):
		(check(value: value == 3, message: "ok value")?)
	else:
		fail(message: "expected ok")?

	if value := parse(""):
		fail(message: f"unexpected {value}")?
	else:
		(check(value: true, message: "error branch")?)
