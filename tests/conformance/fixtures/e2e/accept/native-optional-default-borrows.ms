// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn heap_text(seed: Int) String:
	return ["heap-backed-payload-before-", seed.to_string(), "-and-after-the-number"].join(
		""
	)

fn missing_temporary(seed: Int) Int!:
	absent: Int? := none
	convert := absent.ok_or[Error]
	return convert(Error("missing value at " + heap_text(seed), kind: "ENOENT"))

fn string_temporary(seed: Int) Int!String:
	absent: Int? := none
	convert := absent.ok_or[String]
	return convert(heap_text(seed))

fn fallback_temporary(seed: Int) String:
	values := List[String]()
	get := values.get
	return get(0, heap_text(seed))

interface Fallback:
	fn choose(value: String? = none) String

type Choice:
	fallback: String

impl Fallback for Choice:
	fn choose(value: String?) String:
		if present := value: return present.clone()
		return self.fallback.clone()

test "bound ok_or results own heap-backed temporary causes":
	missing := missing_temporary(1)
	text := string_temporary(2)
	churn := (0..64).map(fn i: heap_text(i + 20))
	expect_equal(missing.err().message, "missing value at " + heap_text(1))?
	expect_equal(text.err(), heap_text(2))?
	expect_equal(churn.length(), 64)?

test "bound ok_or leaves caller causes independent of its result":
	absent: Int? := none
	convert := absent.ok_or[Error]
	var cause = Error("missing value at " + heap_text(3), kind: "ENOENT")
	result := convert(cause)
	cause = Error("missing value at " + heap_text(4), kind: "ENOENT")
	expect_equal(result.err().message, "missing value at " + heap_text(3))?
	expect_equal(cause.message, "missing value at " + heap_text(4))?

	present: Int? := 0
	keep := present.ok_or[Error]
	expect_equal(keep(cause).get(), 0)?
	expect_equal(cause.message, "missing value at " + heap_text(4))?

test "bound native get owns selected heap-backed fallback results":
	result := fallback_temporary(5)
	values := List[String]()
	get := values.get
	var fallback = heap_text(6)
	selected := get(0, fallback)
	fallback = heap_text(7)
	expect_equal(result, heap_text(5))?
	expect_equal(selected, heap_text(6))?
	expect_equal(fallback, heap_text(7))?

test "bound interface adapters preserve heap-backed arguments and results":
	view: Fallback := Choice(heap_text(8))
	choose := view.choose
	result := choose(heap_text(9))
	var argument = heap_text(10)
	selected := choose(argument)
	argument = heap_text(11)
	expect_equal(result, heap_text(9))?
	expect_equal(selected, heap_text(10))?
	expect_equal(argument, heap_text(11))?
	expect_equal(choose(), heap_text(8))?
	expect_equal(choose(none), heap_text(8))?
